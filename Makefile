DOCKER_IMAGE = picorv32-toolchain

.PHONY: all firmware bitstream program docker-image clean submodules

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

# --- Clean ---
clean:
	$(MAKE) -C firmware clean
	rm -rf build/
