CROSS   ?= riscv64-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump

ARCH     = -march=rv32i -mabi=ilp32

# -I. lets any demo's main.c do #include "periph/uart.h" or
# #include "drivers/opt3001.h", resolved relative to this firmware/
# directory regardless of which subfolder it's compiled from.
CFLAGS   = $(ARCH) -Os -Wall -ffreestanding -nostdlib -I.
LDFLAGS  = $(ARCH) -nostdlib -Wl,--no-relax -Wl,--no-warn-rwx-segments

# Which demo subdirectory provides main(). Override to build a different
# one, e.g.:
#   make DEMO=opt3001
DEMO    ?= hello_world

TARGET   = firmware

# The bootloader occupies the first BOOT_SIZE_BYTES of RAM (see
# bootloader/boot.ld); demos are linked to start right after it (see
# linker.ld). Keep these in sync with both.
BOOT_SIZE_BYTES = 2048
BOOT_SIZE_WORDS = 512

.PHONY: all clean

# firmware.hex is the combined bootloader+demo image that actually gets
# baked into BRAM at synthesis time. firmware.bin is the demo alone (linked
# at 0x800), which is what scripts/uart-load.py sends over serial to update
# the running board without re-synthesizing.
all: $(TARGET).hex $(TARGET).dis

# --- Demo ("user firmware"), linked at 0x800 via linker.ld ---
$(TARGET).elf: start.o $(DEMO)/main.o linker.ld
	$(CC) $(LDFLAGS) -T linker.ld -o $@ start.o $(DEMO)/main.o

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

user.hex: $(TARGET).bin
	python3 ../scripts/bin2hex.py $< $@

$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d -M no-aliases $< > $@

# --- Bootloader, linked at 0x0 via bootloader/boot.ld ---
bootloader.elf: start.o bootloader/main.o bootloader/boot.ld
	$(CC) $(LDFLAGS) -T bootloader/boot.ld -o $@ start.o bootloader/main.o

bootloader.bin: bootloader.elf
	$(OBJCOPY) -O binary $< $@

bootloader.hex: bootloader.bin
	python3 ../scripts/bin2hex.py $< $@

# --- Combined image for $readmemh ---
$(TARGET).hex: bootloader.hex user.hex
	python3 ../scripts/merge-hex.py bootloader.hex $(BOOT_SIZE_WORDS) user.hex $@

%.o: %.S
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f start.o */main.o $(TARGET).elf $(TARGET).bin $(TARGET).dis user.hex
	rm -f bootloader.elf bootloader.bin bootloader.hex $(TARGET).hex
