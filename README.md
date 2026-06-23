# PicoRV32 SoC — Arty A7-35T (Open-Source Flow)

Minimal RISC-V SoC targeting the Digilent Arty A7-35T using **only** open-source tools (yosys + nextpnr-xilinx + prjxray + openFPGALoader). No Vivado required.

## Architecture

```
  100 MHz
    |
  [PicoRV32 CPU]
    |  native memory bus
    |--[BRAM 16 KB]     0x00000000
    |--[GPIO 4-bit]     0x10000000
    `--[UART 115200]    0x20000000
```

### UART register map

| Offset | Name     | Access | Description                              |
|--------|----------|--------|------------------------------------------|
| +0x00  | TX_DATA  | W      | Write byte to transmit                   |
| +0x04  | RX_DATA  | R      | Read received byte (clears rx_valid)     |
| +0x08  | STATUS   | R      | bit 0 = tx_busy, bit 1 = rx_valid        |

## File overview

| File | Purpose |
|------|---------|
| `rtl/top.v` | Board-level top: clock, reset, pin connections |
| `rtl/simple_soc.v` | SoC: CPU + address decoder + bus mux |
| `rtl/bram.v` | 16 KB BRAM with hex init and byte-write strobes |
| `rtl/gpio.v` | 4-bit output register for LEDs |
| `rtl/uart.v` | 115200 8N1 TX+RX |
| `rtl/picorv32.v` | **Downloaded** from YosysHQ (auto-fetched by Make) |
| `firmware/start.S` | Reset vector, stack init, BSS clear, call main |
| `firmware/main.c` | LED blink + UART "Hello" |
| `firmware/linker.ld` | Maps everything to 16 KB at 0x00000000 |
| `firmware/Makefile` | Cross-compile firmware → firmware.hex |
| `constraints/board.xdc` | Arty A7-35T pin constraints |
| `docker/Dockerfile` | Full FPGA toolchain (yosys, nextpnr-xilinx, prjxray) |
| `scripts/build-bitstream.sh` | yosys → nextpnr → fasm2frames → bitstream |
| `scripts/program.sh` | openFPGALoader wrapper |
| `scripts/bin2hex.py` | Binary → $readmemh hex converter |

## Prerequisites

### 1. RISC-V GCC toolchain

**macOS (Homebrew):**
```bash
brew tap riscv-software-src/riscv
brew install riscv-tools
# provides riscv64-unknown-elf-gcc — the Makefile uses it with -march=rv32i
```

**Linux (apt):**
```bash
sudo apt install gcc-riscv64-unknown-elf
```

If your prefix differs (e.g. `riscv32-unknown-elf-`), override:
```bash
make -C firmware CROSS=riscv32-unknown-elf-
```

### 2. FPGA toolchain (Docker — recommended)

The synthesis/P&R/bitgen tools (yosys, nextpnr-xilinx, prjxray) run inside a
Docker container. This avoids building them from source on macOS and ensures a
reproducible environment.

```bash
# One-time: build the toolchain image (~20-30 min)
make docker-image

# That's it — `make bitstream` will use Docker automatically.
```

The build script auto-detects whether native tools are installed. If not, it
transparently runs inside the `picorv32-toolchain` Docker image.

<details>
<summary>Alternative: native Linux install (no Docker)</summary>

If you prefer to install the tools natively on Linux:

```bash
# yosys (cmake build, requires cmake >= 3.28)
git clone --recurse-submodules https://github.com/YosysHQ/yosys && cd yosys
cmake -B build && cmake --build build -j$(nproc) && sudo cmake --install build
cd ..

# prjxray (C++ tools + Python package + database)
git clone https://github.com/f4pga/prjxray && cd prjxray
git submodule update --init --recursive
mkdir build && cd build && cmake .. && make -j$(nproc) && sudo make install
cd .. && pip install fasm && pip install .
./download-latest-db.sh
cd ..

# nextpnr-xilinx (with chip database)
git clone --recurse-submodules https://github.com/openXC7/nextpnr-xilinx
cd nextpnr-xilinx
cmake -DARCH=xilinx -DBUILD_GUI=OFF -B build
cmake --build build -j$(nproc) && sudo cmake --install build
# generate chipdb (~1 min):
python3 xilinx/python/bbaexport.py \
    --device xc7a35tcsg324-1 \
    --bba xc7a35tcsg324-1.bba \
    --xray ../prjxray/database/artix7
build/bbasm --le xc7a35tcsg324-1.bba xc7a35tcsg324-1.bin
sudo mkdir -p /usr/share/nextpnr/xilinx-chipdb
sudo cp xc7a35tcsg324-1.bin /usr/share/nextpnr/xilinx-chipdb/
cd ..
```

If the build script cannot find the chipdb or prjxray database, set:
```bash
export NEXTPNR_XILINX_DB=/path/to/dir/containing/xc7a35tcsg324-1.bin
export XRAY_DATABASE_DIR=/path/to/prjxray-db   # must contain artix7/
```

</details>

### 3. openFPGALoader

```bash
# macOS
brew install openfpgaloader

# Linux
sudo apt install openfpgaloader
# or from source: https://github.com/trabucayre/openFPGALoader
```

## Build & run

```bash
# 1. Build firmware (cross-compile C → hex, runs on host)
make firmware

# 2. Build bitstream (runs in Docker if native tools are absent)
make bitstream

# 3. Program FPGA (volatile / SRAM load, runs on host)
make program
```

After programming you should see:
- LEDs counting in binary (LD4–LD7)
- UART output at 115200 8N1 on the USB serial port:
  ```
  --- PicoRV32 SoC on Arty A7 ---
  Hello, RISC-V!
  tick 00000000
  tick 00000001
  ...
  ```

## Monitoring UART

```bash
# macOS
screen /dev/tty.usbserial-* 115200

# Linux
screen /dev/ttyUSB1 115200
# (ttyUSB1 is typically the UART channel; ttyUSB0 is JTAG)
```

## Adapting to a different board

1. Edit `constraints/board.xdc` with your pin assignments.
2. Change `CLK_FREQ` in `rtl/top.v` if your clock differs from 100 MHz.
3. Update `PART` in `scripts/build-bitstream.sh` and regenerate the chipdb.
4. Update the board flag in `scripts/program.sh` (`-b` argument).
5. If using Docker, add the new chipdb to `docker/Dockerfile` and rebuild.
