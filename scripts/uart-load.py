#!/usr/bin/env python3
"""Load a new program into the running SoC over UART, via the bootloader in
firmware/bootloader/main.c -- no re-synthesis/re-programming needed.

Usage:
    python3 scripts/uart-load.py /dev/tty.usbserial-XXXX firmware/firmware.bin

Protocol (must match firmware/bootloader/main.c exactly):
    host  -> board : 'L'                      (repeated until acked)
    board -> host  : 'K'                      (ack, ready for length)
    host  -> board : 4 bytes, length (little-endian u32)
    host  -> board : `length` raw bytes        (the program image)
    host  -> board : 1 byte, checksum (sum of those bytes, mod 256)
    board -> host  : 'K' (loaded) or 'E' (bad length/checksum)

Requires pyserial: pip install pyserial
"""
import sys
import time

try:
    import serial
except ImportError:
    print("ERROR: pyserial not installed. Run: pip install pyserial", file=sys.stderr)
    sys.exit(1)

BAUD = 115200
SYNC_BYTE = b"L"
ACK_BYTE = b"K"
ERR_BYTE = b"E"
MAX_SIZE = 14336

SYNC_WINDOW_SECONDS = 8.0
SYNC_RETRY_INTERVAL = 0.05


def handshake(ser):
    print(f"Reset the board now -- sending sync for up to {SYNC_WINDOW_SECONDS:.0f}s ...")
    deadline = time.time() + SYNC_WINDOW_SECONDS
    while time.time() < deadline:
        ser.write(SYNC_BYTE)
        ser.flush()
        reply = ser.read(1)
        if reply == ACK_BYTE:
            return True
        time.sleep(SYNC_RETRY_INTERVAL)
    return False


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <serial-port> <firmware.bin>", file=sys.stderr)
        sys.exit(1)

    port, bin_path = sys.argv[1], sys.argv[2]

    with open(bin_path, "rb") as f:
        data = f.read()

    if len(data) > MAX_SIZE:
        print(f"ERROR: {bin_path} is {len(data)} bytes, exceeds the "
              f"{MAX_SIZE}-byte user region", file=sys.stderr)
        sys.exit(1)

    checksum = sum(data) & 0xFF

    with serial.Serial(port, BAUD, timeout=0.1) as ser:
        if not handshake(ser):
            print("ERROR: no response from bootloader. Is the board powered, "
                  "on the right port, and did you reset it during the sync "
                  "window?", file=sys.stderr)
            sys.exit(1)

        print(f"Handshake OK, sending {len(data)} bytes ...")
        ser.write(len(data).to_bytes(4, "little"))
        ser.write(data)
        ser.write(bytes([checksum]))
        ser.flush()

        ser.timeout = 5.0
        status = ser.read(1)
        if status == ACK_BYTE:
            print("Load OK, board is running the new firmware.")
        elif status == ERR_BYTE:
            print("ERROR: board rejected the image (bad length or checksum).",
                  file=sys.stderr)
            sys.exit(1)
        else:
            print("ERROR: no final status from board (timed out).", file=sys.stderr)
            sys.exit(1)

        print("--- board output (Ctrl+C to exit) ---")
        ser.timeout = None
        try:
            while True:
                chunk = ser.read(1)
                if chunk:
                    sys.stdout.write(chunk.decode("latin-1"))
                    sys.stdout.flush()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
