#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BITSTREAM="${PROJECT_ROOT}/build/top.bit"
WRITE_FLASH=0

if [ "${1:-}" = "--write-flash" ]; then
    WRITE_FLASH=1
fi

if [ ! -f "$BITSTREAM" ]; then
    echo "ERROR: ${BITSTREAM} not found. Build first with: make bitstream"
    exit 1
fi

echo "==> Programming Arty A7 with openFPGALoader ..."

if [ "$WRITE_FLASH" -eq 1 ]; then
    # Persistent configuration flash load — survives power cycles.
    openFPGALoader -b arty_a7_35t --write-flash "$BITSTREAM"
else
    # Volatile SRAM load — instant, lost on power cycle.
    openFPGALoader -b arty_a7_35t "$BITSTREAM"
fi

echo "==> Done."
