#!/usr/bin/env python3
"""Convert a flat binary to Verilog $readmemh format (32-bit little-endian words)."""
import sys

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.bin output.hex", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    while len(data) % 4:
        data += b"\x00"

    with open(sys.argv[2], "w") as f:
        for i in range(0, len(data), 4):
            word = (data[i]
                    | (data[i + 1] << 8)
                    | (data[i + 2] << 16)
                    | (data[i + 3] << 24))
            f.write(f"{word:08x}\n")

if __name__ == "__main__":
    main()
