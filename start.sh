#!/bin/bash
# =============================================================================
# Palworld ARM64 — Server Startup Script
# Auto-created by the installation script. Reference copy.
# =============================================================================
set -e

export HOME=/home/container
export FEX_ROOTFS_PATH=/home/container/.fex-emu/RootFS/
export XDG_DATA_HOME=/home/container/.local/share
export FEX_APP_DATA_LOCATION=/home/container/.fex-emu
export FEX_APP_CONFIG_LOCATION=/home/container/.fex-emu

log() { echo "[$(date '+%H:%M:%S')] [START] $1"; }

# ---- RootFS Auto-Detection -------------------------------------------------
FEX_ROOTFS_DIR="${HOME}/.fex-emu/RootFS"
FEX_ROOTFS_FILE=""

if [ -d "${FEX_ROOTFS_DIR}" ]; then
    FEX_ROOTFS_FILE=$(find "${FEX_ROOTFS_DIR}" -name "*.sqsh" -type f 2>/dev/null | head -1)
fi

if [ -z "${FEX_ROOTFS_FILE}" ] || [ ! -s "${FEX_ROOTFS_FILE}" ]; then
    log "ERROR: No valid RootFS found in ${FEX_ROOTFS_DIR}"
    log "Please re-run the installation from the panel."
    exit 1
fi
log "RootFS detected: $(basename "${FEX_ROOTFS_FILE}")"

# ---- RootFS Corruption Recovery ---------------------------------------------
ROOTFS_SIZE=$(stat -c%s "${FEX_ROOTFS_FILE}" 2>/dev/null || echo 0)
if [ "${ROOTFS_SIZE}" -lt 104857600 ]; then
    log "WARNING: RootFS corrupted (${ROOTFS_SIZE} bytes). Re-downloading..."
    rm -f "${FEX_ROOTFS_FILE}"
    FEXRootFSFetcher --assume-yes --as-is --distro-name Ubuntu --distro-version 22.04
    if [ $? -ne 0 ]; then
        log "ERROR: RootFS re-download failed"
        exit 1
    fi
    FEX_ROOTFS_FILE=$(find "${FEX_ROOTFS_DIR}" -name "*.sqsh" -type f 2>/dev/null | head -1)
    log "RootFS re-downloaded"
fi

# ---- Config.json Verification / Auto-fix -----------------------------------
FEX_CONFIG="${HOME}/.fex-emu/Config.json"
mkdir -p "${HOME}/.fex-emu"
if [ -f "${FEX_CONFIG}" ]; then
    CURRENT_ROOTFS=$(jq -r '.Config.RootFS // empty' "${FEX_CONFIG}" 2>/dev/null)
    if [ "${CURRENT_ROOTFS}" != "Ubuntu_22_04" ]; then
        log "WARNING: Config.json RootFS is '${CURRENT_ROOTFS}', correcting..."
        cat > "${FEX_CONFIG}" << 'CFGEOF'
{
  "Config": {
    "RootFS": "Ubuntu_22_04"
  }
}
CFGEOF
    fi
else
    cat > "${FEX_CONFIG}" << 'CFGEOF'
{
  "Config": {
    "RootFS": "Ubuntu_22_04"
  }
}
CFGEOF
    log "Config.json created"
fi

# ---- Health Check -----------------------------------------------------------
errors=0
command -v FEXInterpreter &>/dev/null || { log "FAIL: FEXInterpreter not found"; errors=$((errors+1)); }
[ -f "${HOME}/steamcmd/steamcmd.sh" ] || { log "FAIL: SteamCMD not found"; errors=$((errors+1)); }
[ -f "${HOME}/Pal/Binaries/Linux/PalServer-Linux-Shipping" ] || { log "FAIL: PalServer not found"; errors=$((errors+1)); }
[ -d "${FEX_ROOTFS_DIR}" ] && [ -n "$(ls -A "${FEX_ROOTFS_DIR}" 2>/dev/null)" ] || { log "FAIL: RootFS empty"; errors=$((errors+1)); }
if [ $errors -gt 0 ]; then
    log "ERROR: $errors health check(s) failed"
    exit 1
fi
log "Health check passed"

# ---- Steam SDK Fix ----------------------------------------------------------
mkdir -p ~/.steam/sdk64
mkdir -p ~/.steam/sdk32
if [ ! -f ~/.steam/sdk64/steamclient.so ]; then
    cp "${HOME}/steamcmd/linux64/steamclient.so" ~/.steam/sdk64/steamclient.so 2>/dev/null && \
        log "steamclient.so copied to sdk64" || log "WARNING: sdk64 copy failed"
fi
if [ ! -f ~/.steam/sdk32/steamclient.so ]; then
    cp "${HOME}/steamcmd/linux32/steamclient.so" ~/.steam/sdk32/steamclient.so 2>/dev/null && \
        log "steamclient.so copied to sdk32" || log "WARNING: sdk32 copy failed"
fi

# ---- Auto Update ------------------------------------------------------------
if [ "${AUTO_UPDATE}" = "1" ]; then
    log "Auto-update enabled..."
    cd "${HOME}/steamcmd"
    VALIDATE_FLAG=""
    if [ "${VALIDATE}" = "1" ]; then VALIDATE_FLAG="validate"; fi
    FEXInterpreter ./steamcmd.sh \
        +force_install_dir "${HOME}" \
        +login anonymous \
        +app_update 2394010 ${VALIDATE_FLAG} \
        +quit
    log "Update complete"
    cp "${HOME}/steamcmd/linux64/steamclient.so" ~/.steam/sdk64/steamclient.so 2>/dev/null || true
    cp "${HOME}/steamcmd/linux32/steamclient.so" ~/.steam/sdk32/steamclient.so 2>/dev/null || true
fi

# ---- Config Parser ----------------------------------------------------------
bash "${HOME}/config-parser.sh"

# ---- Public IP Auto-Detection -----------------------------------------------
if [ -z "${PUBLIC_IP}" ]; then
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
                curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
                hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    log "Public IP detected: ${PUBLIC_IP}"
fi

# ---- RCON Helper ------------------------------------------------------------
if [ "${RCON_ENABLE}" = "True" ]; then
    (while read -r cmd; do
        mcrcon -s -H "127.0.0.1" -P "${RCON_PORT}" -p "${ADMIN_PASSWORD}" "$cmd" 2>/dev/null
    done) < /dev/stdin &
fi

# ---- Build Launch Command ---------------------------------------------------
CMD=(FEXInterpreter "${HOME}/Pal/Binaries/Linux/PalServer-Linux-Shipping")
CMD+=("Pal")
CMD+=("-port=${SERVER_PORT}")
CMD+=("-publicport=${SERVER_PORT}")
CMD+=("-servername=${SERVER_NAME}")
CMD+=("-players=${MAX_PLAYERS}")
CMD+=("-adminpassword=${ADMIN_PASSWORD}")
[ -n "${PUBLIC_IP}" ] && CMD+=("-publicip=${PUBLIC_IP}")
[ -n "${SERVER_PASSWORD}" ] && CMD+=("-serverpassword=${SERVER_PASSWORD}")
if [ -n "${EXTRA_FLAGS}" ]; then
    IFS=' ' read -ra EA <<< "${EXTRA_FLAGS}"
    CMD+=("${EA[@]}")
fi

# ---- Signal Handling --------------------------------------------------------
cleanup() {
    log "Shutdown signal received..."
    kill -TERM "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    log "Server stopped"
    exit 0
}
trap cleanup SIGTERM SIGINT

# ---- Launch -----------------------------------------------------------------
log "Starting Palworld server..."
log "Command: ${CMD[*]}"
"${CMD[@]}" &
SERVER_PID=$!
wait $SERVER_PID
exit $?
