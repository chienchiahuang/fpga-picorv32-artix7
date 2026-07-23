DOCKER_IMAGE = picorv32-toolchain
DEMO         ?= hello_world
# Prefer the repo's own .venv (pyserial) if present, else fall back to
# whatever's on PATH.
PYTHON       ?= $(if $(wildcard .venv/bin/python3),.venv/bin/python3,python3)

.PHONY: all firmware bitstream program docker-image clean submodules load

all: bitstream

# --- Git submodules (picorv32 etc.) ---
submodules: third_party/picorv32/picorv32.v

third_party/picorv32/picorv32.v:
	git submodule update --init --recursive

# --- Firmware ---
firmware: firmware/firmware.hex

firmware/firmware.hex:
	$(MAKE) -C firmware

# --- Docker toolchain image (one-time, ~20-30 min) ---
docker-image:
	docker build -t $(DOCKER_IMAGE) docker/

# --- Bitstream (auto-falls back to Docker if native tools missing) ---
bitstream: submodules firmware/firmware.hex
	bash scripts/build-bitstream.sh

# --- Program ---
program: build/top.bit
	bash scripts/program.sh

# --- Load a demo over UART, no re-synthesis needed (see firmware/bootloader/) ---
#   make load PORT=/dev/tty.usbserial-XXXX [DEMO=opt3001]
load:
	@if [ -z "$(PORT)" ]; then \
		echo "ERROR: PORT is not set, e.g. make load PORT=/dev/tty.usbserial-XXXX" >&2; \
		exit 1; \
	fi
	$(MAKE) -C firmware DEMO=$(DEMO)
	$(PYTHON) scripts/uart-load.py $(PORT) firmware/firmware.bin

# --- Clean ---
clean:
	$(MAKE) -C firmware clean
	rm -rf build/
