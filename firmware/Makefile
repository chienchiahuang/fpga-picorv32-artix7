CROSS   ?= riscv64-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump

ARCH     = -march=rv32i -mabi=ilp32

# -I. lets any demo's main.c do #include "periph/uart.h" or
# #include "drivers/opt3001.h", resolved relative to this firmware/
# directory regardless of which subfolder it's compiled from.
CFLAGS   = $(ARCH) -Os -Wall -ffreestanding -nostdlib -I.
LDFLAGS  = $(ARCH) -T linker.ld -nostdlib -Wl,--no-relax -Wl,--no-warn-rwx-segments

# Which demo subdirectory provides main(). Override to build a different
# one, e.g.:
#   make DEMO=opt3001
DEMO    ?= hello_world

TARGET   = firmware
OBJS     = start.o $(DEMO)/main.o

.PHONY: all clean

all: $(TARGET).hex $(TARGET).dis

$(TARGET).elf: $(OBJS) linker.ld
	$(CC) $(LDFLAGS) -o $@ $(OBJS)

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(TARGET).hex: $(TARGET).bin
	python3 ../scripts/bin2hex.py $< $@

$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d -M no-aliases $< > $@

%.o: %.S
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f start.o */main.o $(TARGET).elf $(TARGET).bin $(TARGET).hex $(TARGET).dis
