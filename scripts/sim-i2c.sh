#!/usr/bin/env bash
# Runs the rtl/i2c.v testbench with Icarus Verilog.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_DIR="${PROJECT_ROOT}/sim"
BUILD_DIR="${PROJECT_ROOT}/build/sim"

command -v iverilog >/dev/null || { echo "ERROR: iverilog not found (brew install icarus-verilog / apt install iverilog)"; exit 1; }

mkdir -p "$BUILD_DIR"

echo "==> Compiling testbench ..."
iverilog -g2012 -o "${BUILD_DIR}/tb_i2c.vvp" \
    "${PROJECT_ROOT}/rtl/i2c.v" \
    "${SIM_DIR}/tb_i2c.v"

echo "==> Running ..."
cd "$BUILD_DIR"
vvp tb_i2c.vvp | tee sim.log

echo "==> Waveform: ${BUILD_DIR}/tb_i2c.vcd"

grep -q "ALL TESTS PASSED" sim.log
