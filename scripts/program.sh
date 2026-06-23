#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BITSTREAM="${PROJECT_ROOT}/build/top.bit"

if [ ! -f "$BITSTREAM" ]; then
    echo "ERROR: ${BITSTREAM} not found. Build first with: make bitstream"
    exit 1
fi

echo "==> Programming Arty A7 with openFPGALoader ..."

# Volatile (SRAM) load — instant, lost on power cycle
openFPGALoader -b arty_a7_35t "$BITSTREAM"

# To write to SPI flash (persistent across power cycles), use:
#   openFPGALoader -b arty_a7_35t --write-flash "$BITSTREAM"

echo "==> Done."
