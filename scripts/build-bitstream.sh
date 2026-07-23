#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
RTL_DIR="${PROJECT_ROOT}/rtl"
XDC="${PROJECT_ROOT}/constraints/board.xdc"
FW_APP="${FW_APP:-hello_world}"
FW_HEX="${FW_HEX:-${PROJECT_ROOT}/build/firmware/${FW_APP}/firmware.hex}"

PART="xc7a35tcsg324-1"
DOCKER_IMAGE="picorv32-toolchain"

# --- Check firmware ---
if [ ! -f "$FW_HEX" ]; then
    echo "ERROR: ${FW_HEX} not found. Build firmware first:"
    echo "  make firmware"
    exit 1
fi

# --- Docker fallback if native tools are missing ---
if ! command -v yosys >/dev/null 2>&1 || \
   ! command -v nextpnr-xilinx >/dev/null 2>&1; then
    if docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
        echo "==> Native tools not found; running inside Docker ..."
        exec docker run --rm \
            -e "FW_APP=${FW_APP}" \
            -v "${PROJECT_ROOT}:/workspace" \
            -w /workspace \
            "$DOCKER_IMAGE" \
            bash scripts/build-bitstream.sh
    else
        echo "ERROR: yosys / nextpnr-xilinx not found, and Docker image '${DOCKER_IMAGE}' not built."
        echo "  Build the Docker toolchain image first:"
        echo "    make docker-image"
        exit 1
    fi
fi

# --- Locate chipdb ---
CHIPDB=""
for dir in \
    "${NEXTPNR_XILINX_DB:-}" \
    "/usr/share/nextpnr/xilinx-chipdb" \
    "/usr/local/share/nextpnr/xilinx-chipdb" \
    "${HOME}/.local/share/nextpnr/xilinx-chipdb" \
    "${HOME}/nextpnr-xilinx/xilinx/xc7/chipdb"; do
    if [ -f "${dir}/${PART}.bin" ] 2>/dev/null; then
        CHIPDB="${dir}/${PART}.bin"
        break
    fi
done

if [ -z "$CHIPDB" ]; then
    echo "ERROR: chipdb not found for ${PART}."
    echo "  Set NEXTPNR_XILINX_DB to the directory containing ${PART}.bin"
    exit 1
fi

# --- Locate prjxray database ---
XRAY_DB=""
for dir in \
    "${XRAY_DATABASE_DIR:-}" \
    "/usr/share/xc7/prjxray-db" \
    "/usr/local/share/xc7/prjxray-db" \
    "/opt/prjxray/database" \
    "${HOME}/.local/share/prjxray/database"; do
    if [ -d "${dir}/artix7" ] 2>/dev/null; then
        XRAY_DB="${dir}"
        break
    fi
done

if [ -z "$XRAY_DB" ]; then
    echo "ERROR: prjxray database not found."
    echo "  Set XRAY_DATABASE_DIR to the prjxray-db root (containing artix7/)."
    exit 1
fi

mkdir -p "$BUILD_DIR"

# rtl/top.v's FIRMWARE_HEX default points here. Stage the resolved per-app
# image at this fixed path rather than overriding the parameter at
# synthesis time: Yosys's Verilog frontend resolves $readmemh's file
# argument (in rtl/bram.v) while parsing, before any later `chparam` command
# gets a chance to run -- so `chparam -set FIRMWARE_HEX ... top` is silently
# too late and has no effect on which file actually gets read.
cp "$FW_HEX" "${BUILD_DIR}/firmware.hex"

echo "==> Synthesizing with yosys ..."
yosys -q -p "
    read_verilog ${RTL_DIR}/picorv32.v;
    read_verilog ${RTL_DIR}/bram.v;
    read_verilog ${RTL_DIR}/gpio.v;
    read_verilog ${RTL_DIR}/uart.v;
    read_verilog ${RTL_DIR}/i2c.v;
    read_verilog ${RTL_DIR}/simple_soc.v;
    read_verilog ${RTL_DIR}/top.v;
    synth_xilinx -flatten -abc9 -arch xc7 -top top;
    write_json ${BUILD_DIR}/top.json
"

echo "==> Place & route with nextpnr-xilinx ..."
nextpnr-xilinx \
    --chipdb "$CHIPDB" \
    --xdc "$XDC" \
    --json "${BUILD_DIR}/top.json" \
    --fasm "${BUILD_DIR}/top.fasm" \
    --router router2

echo "==> Generating frames ..."
fasm2frames.py \
    --db-root "${XRAY_DB}/artix7" \
    --part "$PART" \
    "${BUILD_DIR}/top.fasm" \
    > "${BUILD_DIR}/top.frames"

echo "==> Generating bitstream ..."
xc7frames2bit \
    --part_file "${XRAY_DB}/artix7/${PART}/part.yaml" \
    --part_name "$PART" \
    --frm_file "${BUILD_DIR}/top.frames" \
    --output_file "${BUILD_DIR}/top.bit"

echo "==> Done: ${BUILD_DIR}/top.bit"
