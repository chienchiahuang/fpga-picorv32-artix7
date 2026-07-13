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
    |--[UART 115200]    0x20000000
    `--[I2C master]     0x30000000
```

### UART register map

| Offset | Name     | Access | Description                              |
|--------|----------|--------|------------------------------------------|
| +0x00  | TX_DATA  | W      | Write byte to transmit                   |
| +0x04  | RX_DATA  | R      | Read received byte (clears rx_valid)     |
| +0x08  | STATUS   | R      | bit 0 = tx_busy, bit 1 = rx_valid        |

### I2C register map

Simple polled master, 100 kHz, no clock stretching (`rtl/i2c.v`), on Pmod JA
pins 1-2 (SDA/SCL) — needs external pull-up resistors (e.g. 4.7k to 3.3V);
the board provides none.

| Offset | Name    | Access | Description                                                                             |
|--------|---------|--------|-------------------------------------------------------------------------------------------|
| +0x00  | CTRL    | W      | Command bits: bit0 START, bit1 STOP, bit2 WR, bit3 RD, bit4 NACK (send NACK on this RD)   |
| +0x04  | TXDATA  | R/W    | Byte to send on the next WR                                                              |
| +0x08  | RXDATA  | R      | Byte received by the last RD                                                             |
| +0x0C  | STATUS  | R      | bit 0 = busy, bit 1 = ack_error (slave NACKed a WR)                                       |

Command bits may be combined in one CTRL write (e.g. `START|WR` starts a
transaction and sends the first byte). Firmware polls STATUS.busy until a
command completes. Example — write 0xAA to device 0x50, then read one byte:

```c
I2C_TXDATA = (0x50 << 1) | 0;                          // address + write bit
I2C_CTRL   = I2C_CMD_START | I2C_CMD_WR;
while (I2C_STATUS & I2C_STATUS_BUSY);

I2C_TXDATA = 0xAA;
I2C_CTRL   = I2C_CMD_WR | I2C_CMD_STOP;
while (I2C_STATUS & I2C_STATUS_BUSY);

I2C_TXDATA = (0x50 << 1) | 1;                          // address + read bit
I2C_CTRL   = I2C_CMD_START | I2C_CMD_WR;
while (I2C_STATUS & I2C_STATUS_BUSY);

I2C_CTRL   = I2C_CMD_RD | I2C_CMD_NACK | I2C_CMD_STOP; // single-byte read
while (I2C_STATUS & I2C_STATUS_BUSY);
uint8_t value = I2C_RXDATA;
```

## File overview

| File | Purpose |
|------|---------|
| `rtl/top.v` | Board-level top: clock, reset, pin connections |
| `rtl/simple_soc.v` | SoC: CPU + address decoder + bus mux |
| `rtl/bram.v` | 16 KB BRAM with hex init and byte-write strobes |
| `rtl/gpio.v` | 4-bit output register for LEDs |
| `rtl/uart.v` | 115200 8N1 TX+RX |
| `rtl/i2c.v` | Polled I2C master, 100 kHz, no clock stretching |
| `rtl/picorv32.v` | **Downloaded** from YosysHQ (auto-fetched by Make) |
| `sim/tb_i2c.v` | Self-checking testbench for `rtl/i2c.v` (run via `scripts/sim-i2c.sh`) |
| `firmware/start.S` | Reset vector, stack init, BSS clear, call main |
| `firmware/periph/` | On-chip SoC peripheral register maps + helpers (GPIO/UART/I2C) |
| `firmware/drivers/` | Drivers for external devices sitting on top of `periph/` (e.g. `opt3001.h`) |
| `firmware/hello_world/main.c` | Default firmware: LED blink + UART "Hello" |
| `firmware/opt3001/main.c` | Reads an OPT3001 ambient light sensor over I2C, prints lux over UART |
| `firmware/i2c_scan/main.c` | Scans the I2C bus and reports which addresses ACK |
| `firmware/linker.ld` | Maps everything to 16 KB at 0x00000000 |
| `firmware/Makefile` | Cross-compile firmware → firmware.hex (`DEMO=<subdir>` selects which demo's `main.c` to build) |
| `constraints/board.xdc` | Arty A7-35T pin constraints |
| `docker/Dockerfile` | Full FPGA toolchain (yosys, nextpnr-xilinx, prjxray) |
| `scripts/build-bitstream.sh` | yosys → nextpnr → fasm2frames → bitstream |
| `scripts/program.sh` | openFPGALoader wrapper |
| `scripts/bin2hex.py` | Binary → $readmemh hex converter |
| `scripts/sim-i2c.sh` | Runs `sim/tb_i2c.v` with Icarus Verilog |

## Firmware organization

```
firmware/
  periph/           on-chip SoC peripheral registers + helpers (gpio.h, uart.h, i2c.h, util.h)
  drivers/          drivers for external devices sitting on top of periph/ (e.g. opt3001.h)
  hello_world/      demo: main.c
  opt3001/          demo: main.c
  i2c_scan/         demo: main.c
  start.S, linker.ld, Makefile
```

- **`periph/`** wraps this SoC's own memory-mapped registers (the blocks in
  `rtl/`) — one header per peripheral, `static inline` functions, no `.c`
  files to compile separately.
- **`drivers/`** is for chips attached *through* a peripheral (e.g. an I2C
  sensor). A driver only depends on `periph/`, never on a specific demo, so
  it can be reused across demos.
- Each demo is its own subdirectory with a single `main.c`; only one demo is
  built into `firmware.hex` at a time (see `DEMO=` below).
- To add a new demo: create `firmware/<name>/main.c`, `#include` whatever
  `periph/`/`drivers/` headers it needs, and build with
  `make -C firmware DEMO=<name>`.

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

`make firmware` builds `firmware/hello_world/main.c` by default. To build a
different demo, pass `DEMO=<subdirectory>` through to the firmware build,
e.g.:

```bash
make -C firmware DEMO=opt3001
make bitstream   # picks up whatever firmware/firmware.hex was last built
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
