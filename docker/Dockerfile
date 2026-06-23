FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ── Build dependencies ──────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    build-essential clang bison flex gawk \
    libreadline-dev tcl-dev libffi-dev pkg-config \
    python3 python3-pip python3-yaml python3-setuptools \
    libboost-all-dev \
    cmake zlib1g-dev libeigen3-dev \
    git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ── yosys (cmake build, requires cmake >= 3.28) ────────────────────
RUN git clone --depth 1 --recurse-submodules --shallow-submodules \
        https://github.com/YosysHQ/yosys /tmp/yosys && \
    cd /tmp/yosys && \
    cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local && \
    cmake --build build -j"$(nproc)" && \
    cmake --install build && \
    rm -rf /tmp/yosys

# ── prjxray (C++ tools + Python package + database) ────────────────
RUN git clone https://github.com/f4pga/prjxray /opt/prjxray && \
    cd /opt/prjxray && git submodule update --init --recursive && \
    mkdir build && cd build && cmake .. && make -j"$(nproc)" && make install && \
    cd /opt/prjxray && pip3 install --break-system-packages fasm && \
    pip3 install --break-system-packages .

# The git repo only has stubs; real data lives in prjxray-db
RUN cd /opt/prjxray && ./download-latest-db.sh

RUN chmod +x /opt/prjxray/utils/fasm2frames.py && \
    ln -sf /opt/prjxray/utils/fasm2frames.py /usr/local/bin/fasm2frames.py

# ── nextpnr-xilinx ─────────────────────────────────────────────────
RUN git clone --recurse-submodules \
        https://github.com/openXC7/nextpnr-xilinx /opt/nextpnr-xilinx && \
    cd /opt/nextpnr-xilinx && \
    cmake -DARCH=xilinx -DBUILD_GUI=OFF -B build && \
    cmake --build build -j"$(nproc)" && \
    cmake --install build

# ── Generate chipdb for xc7a35t (Arty A7-35T) ──────────────────────
RUN cd /opt/nextpnr-xilinx && \
    python3 xilinx/python/bbaexport.py \
        --device xc7a35tcsg324-1 \
        --bba xc7a35tcsg324-1.bba \
        --xray /opt/prjxray/database/artix7 && \
    build/bbasm --le xc7a35tcsg324-1.bba xc7a35tcsg324-1.bin && \
    mkdir -p /usr/share/nextpnr/xilinx-chipdb && \
    mv xc7a35tcsg324-1.bin /usr/share/nextpnr/xilinx-chipdb/ && \
    rm -f xc7a35tcsg324-1.bba

# ── Environment ─────────────────────────────────────────────────────
ENV NEXTPNR_XILINX_DB=/usr/share/nextpnr/xilinx-chipdb
ENV XRAY_DATABASE_DIR=/opt/prjxray/database

WORKDIR /workspace
