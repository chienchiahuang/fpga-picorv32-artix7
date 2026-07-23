#!/usr/bin/env python3
"""Combine a bootloader $readmemh image and a user-firmware $readmemh image
into a single memory image, padding the bootloader up to its reserved word
count so the user image lands at the right address. Both inputs are the
one-word-per-line hex format produced by bin2hex.py."""
import sys


def read_words(path):
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def main():
    if len(sys.argv) != 5:
        print(f"Usage: {sys.argv[0]} boot.hex boot_words user.hex output.hex",
              file=sys.stderr)
        sys.exit(1)

    boot_path, boot_words_arg, user_path, out_path = sys.argv[1:5]
    boot_words = int(boot_words_arg)

    boot = read_words(boot_path)
    if len(boot) > boot_words:
        print(f"ERROR: bootloader is {len(boot)} words, "
              f"only {boot_words} reserved", file=sys.stderr)
        sys.exit(1)
    boot += ["00000000"] * (boot_words - len(boot))

    user = read_words(user_path)

    with open(out_path, "w") as f:
        for word in boot + user:
            f.write(word + "\n")


if __name__ == "__main__":
    main()
