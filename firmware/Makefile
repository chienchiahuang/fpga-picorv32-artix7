CROSS   ?= riscv64-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump

ARCH     = -march=rv32i -mabi=ilp32

# -I. lets any app's main.c do #include "periph/uart.h" or
# #include "drivers/opt3001.h", resolved relative to this firmware/
# directory regardless of which subfolder it's compiled from.
CFLAGS   = $(ARCH) -Os -Wall -ffreestanding -nostdlib -I.
LDFLAGS  = $(ARCH) -nostdlib -Wl,--no-relax -Wl,--no-warn-rwx-segments

# Which sample subdirectory provides main(). Override to build a different
# one, e.g.:
#   make APP=opt3001
# DEMO is kept as a compatibility alias.
APP     ?= hello_world
ifdef DEMO
APP := $(DEMO)
endif
APP_DIR := samples/$(APP)

TARGET   = firmware

BUILD_ROOT = ../build/firmware
BUILD_DIR  = $(BUILD_ROOT)/$(APP)

TARGET_ELF = $(BUILD_DIR)/$(TARGET).elf
TARGET_BIN = $(BUILD_DIR)/$(TARGET).bin
TARGET_HEX = $(BUILD_DIR)/$(TARGET).hex
TARGET_DIS = $(BUILD_DIR)/$(TARGET).dis
USER_HEX   = $(BUILD_DIR)/user.hex

START_O    = $(BUILD_DIR)/start.o
APP_O      = $(BUILD_DIR)/$(APP_DIR)/main.o
BOOT_O     = $(BUILD_DIR)/bootloader/main.o
BOOT_ELF   = $(BUILD_DIR)/bootloader.elf
BOOT_BIN   = $(BUILD_DIR)/bootloader.bin
BOOT_HEX   = $(BUILD_DIR)/bootloader.hex

# The bootloader occupies the first BOOT_SIZE_BYTES of RAM (see
# bootloader/boot.ld); apps are linked to start right after it (see
# linker.ld). Keep these in sync with both.
BOOT_SIZE_BYTES = 2048
BOOT_SIZE_WORDS = 512

.PHONY: all clean

# firmware.hex is the combined bootloader+app image that actually gets
# baked into BRAM at synthesis time. firmware.bin is the app alone (linked
# at 0x800), which is what scripts/uart-load.py sends over serial to update
# the running board without re-synthesizing.
all: $(TARGET_HEX) $(TARGET_DIS)

# --- Loadable application, linked at 0x800 via linker.ld ---
$(TARGET_ELF): $(START_O) $(APP_O) linker.ld
	@mkdir -p $(dir $@)
	$(CC) $(LDFLAGS) -T linker.ld -o $@ $(START_O) $(APP_O)

$(TARGET_BIN): $(TARGET_ELF)
	@mkdir -p $(dir $@)
	$(OBJCOPY) -O binary $< $@

$(USER_HEX): $(TARGET_BIN)
	@mkdir -p $(dir $@)
	python3 ../scripts/bin2hex.py $< $@

$(TARGET_DIS): $(TARGET_ELF)
	@mkdir -p $(dir $@)
	$(OBJDUMP) -d -M no-aliases $< > $@

# --- Bootloader, linked at 0x0 via bootloader/boot.ld ---
$(BOOT_ELF): $(START_O) $(BOOT_O) bootloader/boot.ld
	@mkdir -p $(dir $@)
	$(CC) $(LDFLAGS) -T bootloader/boot.ld -o $@ $(START_O) $(BOOT_O)

$(BOOT_BIN): $(BOOT_ELF)
	@mkdir -p $(dir $@)
	$(OBJCOPY) -O binary $< $@

$(BOOT_HEX): $(BOOT_BIN)
	@mkdir -p $(dir $@)
	python3 ../scripts/bin2hex.py $< $@

# --- Combined image for $readmemh ---
$(TARGET_HEX): $(BOOT_HEX) $(USER_HEX)
	@mkdir -p $(dir $@)
	python3 ../scripts/merge-hex.py $(BOOT_HEX) $(BOOT_SIZE_WORDS) $(USER_HEX) $@

$(START_O): start.S
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(APP_O): $(APP_DIR)/main.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BOOT_O): bootloader/main.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -rf $(BUILD_ROOT)
