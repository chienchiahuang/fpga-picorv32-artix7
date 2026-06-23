CROSS   ?= riscv64-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump

ARCH     = -march=rv32i -mabi=ilp32

CFLAGS   = $(ARCH) -Os -Wall -ffreestanding -nostdlib
LDFLAGS  = $(ARCH) -T linker.ld -nostdlib -Wl,--no-relax -Wl,--no-warn-rwx-segments

TARGET   = firmware
OBJS     = start.o main.o

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
	rm -f $(OBJS) $(TARGET).elf $(TARGET).bin $(TARGET).hex $(TARGET).dis
