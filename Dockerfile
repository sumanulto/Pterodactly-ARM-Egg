# ==============================================================================
# Palworld ARM64 Docker Image — Multi-stage build
# For Oracle Cloud Ampere A1 (aarch64) + Pterodactyl
#
# FEX installation uses the OFFICIAL method:
#   PPA: ppa:fex-emu/fex  (NOT ppa:fex-emu/fex-emu — that is dead)
#   Packages: fex-emu-armv8.{0,2,4} (binfmt not needed — we call FEXInterpreter directly)
#   Docs: https://github.com/FEX-Emu/FEX#readme
# ==============================================================================

# ==============================================================================
# Stage 1: Builder — install FEX-Emu from official PPA and snapshot everything
# ==============================================================================
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# --- Add official FEX PPA and install FEX packages ---
# The correct PPA is ppa:fex-emu/fex (NOT ppa:fex-emu/fex-emu which is dead).
# Package names are fex-emu-armv8.{0,2,4}, NOT "FEXInterpreter".
# CPU version is detected at build time to install the optimal package.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        software-properties-common \
        gpg-agent && \
    add-apt-repository -y ppa:fex-emu/fex && \
    apt-get update

# Detect ARM CPU features and install the matching FEX package
# v8.4 > v8.2 > v8.0 fallback
RUN CPU_FLAGS="$(grep 'Features' /proc/cpuinfo | head -1)" && \
    FEX_PKG="fex-emu-armv8.0" && \
    if echo "$CPU_FLAGS" | grep -q "asimddp" && \
       echo "$CPU_FLAGS" | grep -q "flagm"  && \
       echo "$CPU_FLAGS" | grep -q "ilrcpc" && \
       echo "$CPU_FLAGS" | grep -q "uscat"; then \
        FEX_PKG="fex-emu-armv8.4"; \
    elif echo "$CPU_FLAGS" | grep -q "dcpop"; then \
        FEX_PKG="fex-emu-armv8.2"; \
    fi && \
    echo "=== FEX: installing $FEX_PKG ===" && \
    apt-get install -y --no-install-recommends "$FEX_PKG"
    # NOTE: fex-emu-binfmt32/64 are intentionally excluded.
    # Their post-install scripts require systemd-binfmt which doesn't exist in Docker.
    # We call FEXInterpreter directly so binfmt_misc registration is unnecessary.

# --- Collect every FEX binary, its shared-library deps, and data dirs ---
# Uses cpio for fast bulk copy (preserves paths, no per-file shell forks)
RUN mkdir -p /fex-staging && cd / && \
    { \
      for pkg in $(dpkg -l 2>/dev/null | grep '^ii.*fex-emu' | awk '{print $2}'); do \
          dpkg -L "$pkg" 2>/dev/null; \
      done | grep -E '^/' | grep -v '/dpkg\|/doc\|/man\|/share/doc' ; \
      find /usr/bin -maxdepth 1 -name 'FEX*' -type f 2>/dev/null | \
          xargs ldd 2>/dev/null | awk '/=>/{print $3}' | sort -u | \
          grep -v 'not found' ; \
      for dir in /usr/lib/aarch64-linux-gnu/fex-emu /usr/lib/aarch64-linux-gnu/FEX \
                 /usr/lib/fex-emu /usr/share/fex-emu /etc/fex-emu; do \
          [ -d "$dir" ] && find "$dir" -type f ; \
      done ; \
    } | sort -u | cpio -pdmu /fex-staging/ 2>/dev/null && \
    tar -czf /fex-artifact.tar.gz -C /fex-staging .

# ==============================================================================
# Stage 2: Runtime — lean image with everything pre-installed
# ==============================================================================
FROM ubuntu:22.04

LABEL maintainer="Palworld ARM64 Egg"
LABEL description="Palworld Dedicated Server for ARM64 with FEX-Emu x86 emulation"

ENV DEBIAN_FRONTEND=noninteractive

# Runtime-only packages — no build tools, no apt cache
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        squashfuse \
        fuse3 \
        libfuse3-3 \
        libfuse2 \
        curl \
        ca-certificates \
        tar \
        xz-utils \
        gzip \
        unzip \
        jq \
        procps \
        libstdc++6 && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/*

# Restore FEX-Emu from builder
COPY --from=builder /fex-artifact.tar.gz /tmp/fex.tar.gz
RUN tar -xzf /tmp/fex.tar.gz -C / && rm /tmp/fex.tar.gz

# mcrcon — ARM64 native RCON client
RUN curl -sSL -o /tmp/mcrcon.tar.gz \
        "https://github.com/Tiiffi/mcrcon/releases/download/v0.7.2/mcrcon-0.7.2-linux-arm64.tar.gz" && \
    tar -xzf /tmp/mcrcon.tar.gz -C /usr/local/bin mcrcon && \
    chmod +x /usr/local/bin/mcrcon && \
    rm -f /tmp/mcrcon.tar.gz

# ---- FEX / container environment ----
ENV HOME=/home/container
ENV FEX_ROOTFS_PATH=/home/container/.fex-emu/RootFS/
ENV XDG_DATA_HOME=/home/container/.local/share
ENV FEX_APP_DATA_LOCATION=/home/container/.fex-emu
ENV FEX_APP_CONFIG_LOCATION=/home/container/.fex-emu

WORKDIR /home/container
