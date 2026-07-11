# ==============================================================================
# Palworld ARM64 Docker Image — Multi-stage build
# For Oracle Cloud Ampere A1 (aarch64) + Pterodactyl
# ==============================================================================

# ---- Stage 1: Builder — install FEX-Emu and snapshot its files ----
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common gpg-agent && \
    add-apt-repository -y ppa:fex-emu/fex-emu && \
    apt-get update && \
    apt-get install -y --no-install-recommends FEXInterpreter FEXRootFSFetcher

# Collect every FEX binary, its shared-library dependencies, and data dirs
RUN mkdir -p /fex-staging && \
    (dpkg -L FEXInterpreter FEXRootFSFetcher 2>/dev/null || true) | \
        grep -E '^/' | grep -v '/dpkg\|/doc\|/man\|/share/doc' | sort -u | \
        while IFS= read -r f; do \
            [ -e "$f" ] || continue; \
            mkdir -p "/fex-staging$(dirname "$f")"; \
            cp -a "$f" "/fex-staging$f" 2>/dev/null || true; \
        done && \
    for bin in /usr/bin/FEX*; do \
        [ -x "$bin" ] || continue; \
        ldd "$bin" 2>/dev/null | awk '/=>/{print $3}' | while read lib; do \
            [ -f "$lib" ] || continue; \
            mkdir -p "/fex-staging$(dirname "$lib")"; \
            cp -a "$lib" "/fex-staging$lib" 2>/dev/null || true; \
        done; \
    done && \
    for dir in /usr/lib/aarch64-linux-gnu/FEX /usr/share/fex-emu /etc/fex-emu; do \
        [ -d "$dir" ] && cp -a "$dir" "/fex-staging$dir" 2>/dev/null || true; \
    done && \
    tar -czf /fex-artifact.tar.gz -C /fex-staging .

# ---- Stage 2: Runtime — lean image with everything pre-installed ----
FROM ubuntu:22.04

LABEL maintainer="Palworld ARM64 Egg"
LABEL description="Palworld Dedicated Server for ARM64 with FEX-Emu x86 emulation"

ENV DEBIAN_FRONTEND=noninteractive

# Runtime-only packages (no build tools, no apt cache)
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
