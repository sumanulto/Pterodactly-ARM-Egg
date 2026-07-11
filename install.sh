#!/bin/bash
# =============================================================================
# Palworld ARM64 — Installation Script
# Runs inside the Pterodactyl installer container.
# Server files live at /mnt/server (mapped to /home/container at runtime).
# =============================================================================
set -e

export HOME=/mnt/server
cd /mnt/server

log() { echo "[$(date '+%H:%M:%S')] [INSTALL] $1"; }

log "============================================="
log "  Palworld ARM64 — FEX-Emu Installer"
log "============================================="

# --- Verify ARM64 ---
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    log "ERROR: This egg requires ARM64 (aarch64). Detected: $ARCH"
    exit 1
fi
log "Architecture: $ARCH OK"

# =============================================================================
# 1. Download Ubuntu 22.04 RootFS (fully non-interactive)
# =============================================================================
FEX_ROOTFS_DIR="${HOME}/.fex-emu/RootFS"
FEX_ROOTFS_FILE="${FEX_ROOTFS_DIR}/Ubuntu_22_04.sqsh"
mkdir -p "${FEX_ROOTFS_DIR}"

if [ ! -f "${FEX_ROOTFS_FILE}" ] || [ ! -s "${FEX_ROOTFS_FILE}" ]; then
    log "[1/6] Downloading Ubuntu 22.04 RootFS (non-interactive)..."
    export FEX_ROOTFS_PATH="${FEX_ROOTFS_DIR}"
    FEXRootFSFetcher --assume-yes --as-is --distro-name Ubuntu --distro-version 22.04
    if [ $? -ne 0 ] || [ ! -f "${FEX_ROOTFS_FILE}" ]; then
        log "ERROR: RootFS download failed"
        exit 1
    fi
    log "RootFS downloaded: $(du -h "${FEX_ROOTFS_FILE}" | cut -f1)"
else
    log "[1/6] RootFS already exists, skipping"
fi

# =============================================================================
# 2. Generate FEX Config.json (never require manual creation)
# =============================================================================
FEX_CONFIG_DIR="${HOME}/.fex-emu"
FEX_CONFIG="${FEX_CONFIG_DIR}/Config.json"
mkdir -p "${FEX_CONFIG_DIR}"

if [ ! -f "${FEX_CONFIG}" ]; then
    cat > "${FEX_CONFIG}" << 'CFGEOF'
{
  "Config": {
    "RootFS": "Ubuntu_22_04"
  }
}
CFGEOF
    log "[2/6] Created FEX Config.json"
else
    CURRENT=$(jq -r '.Config.RootFS // empty' "${FEX_CONFIG}" 2>/dev/null)
    if [ "${CURRENT}" != "Ubuntu_22_04" ]; then
        cat > "${FEX_CONFIG}" << 'CFGEOF'
{
  "Config": {
    "RootFS": "Ubuntu_22_04"
  }
}
CFGEOF
        log "[2/6] Fixed Config.json (was ${CURRENT})"
    else
        log "[2/6] Config.json OK"
    fi
fi

# =============================================================================
# 3. Download SteamCMD
# =============================================================================
mkdir -p /mnt/server/steamcmd /mnt/server/steamapps
if [ ! -f /mnt/server/steamcmd/steamcmd.sh ]; then
    log "[3/6] Downloading SteamCMD..."
    cd /tmp
    curl -sSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
    tar -xzf steamcmd.tar.gz -C /mnt/server/steamcmd
    rm -f steamcmd.tar.gz
    log "SteamCMD installed"
else
    log "[3/6] SteamCMD already exists, skipping"
fi

# =============================================================================
# 4. Install Palworld via SteamCMD under FEX
# =============================================================================
log "[4/6] Installing Palworld via SteamCMD..."
export FEX_ROOTFS_PATH="${FEX_ROOTFS_DIR}"
cd /mnt/server/steamcmd

VALIDATE_FLAG=""
if [ "${VALIDATE}" = "1" ]; then
    VALIDATE_FLAG="validate"
    log "Validation enabled"
fi

FEXInterpreter ./steamcmd.sh \
    +force_install_dir /mnt/server \
    +login anonymous \
    +app_update 2394010 ${VALIDATE_FLAG} \
    +quit

if [ $? -ne 0 ]; then
    log "ERROR: SteamCMD failed to install Palworld"
    exit 1
fi
log "Palworld installation complete"

# =============================================================================
# 5. Copy steamclient.so (fixes SteamAPI_Init missing error)
# =============================================================================
log "[5/6] Setting up Steam SDK..."
mkdir -p /mnt/server/.steam/sdk64
mkdir -p /mnt/server/.steam/sdk32
cp -v /mnt/server/steamcmd/linux64/steamclient.so /mnt/server/.steam/sdk64/
cp -v /mnt/server/steamcmd/linux32/steamclient.so /mnt/server/.steam/sdk32/

# =============================================================================
# 6. Write runtime scripts (start.sh + config-parser.sh)
# =============================================================================
log "[6/6] Writing runtime scripts..."

# ---------- config-parser.sh ----------
cat > /mnt/server/config-parser.sh << 'CPARSE'
#!/bin/bash
# =============================================================================
# Palworld ARM64 — Config Parser (create + update PalWorldSettings.ini)
# =============================================================================
CONFIG_DIR="/home/container/Pal/Saved/Config/LinuxServer"
CONFIG_FILE="${CONFIG_DIR}/PalWorldSettings.ini"
mkdir -p "${CONFIG_DIR}"

update_ini_field() {
    local file="$1" key="$2" value="$3"
    if grep -q "${key}=" "$file" 2>/dev/null; then
        sed -i -E "s/(${key}=)(\"[^\"]*\"|[^,)]*)/\1${value}/g" "$file"
    else
        sed -i -E "s/\)(\s*)$/.${key}=${value})\1/" "$file"
    fi
}

if [ ! -f "${CONFIG_FILE}" ]; then
    cat > "${CONFIG_FILE}" << 'PEOF'
[/Script/Pal.PalGameWorldSettings]
OptionSettings=(Difficulty=None,DayTimeSpeedRate=1.0,NightTimeSpeedRate=1.0,ExpRate=1.0,PalCaptureRate=1.0,PalDamageRateAttack=1.0,PalDamageRateDefense=1.0,PlayerDamageRateAttack=1.0,PlayerDamageRateDefense=1.0,PlayerStomachDecreaseRate=1.0,PlayerStaminaDecreaseRate=1.0,PlayerAutoHPRegenRate=1.0,PlayerAutoHpRegenRateInSleep=1.0,PalStomachDecreaseRate=1.0,PalAutoHPRegenRate=1.0,PalAutoHpRegenRateInSleep=1.0,BuildObjectDamageRate=1.0,BuildObjectDeteriorationDamageRate=1.0,CollectionDropRate=1.0,CollectionObjectHpRate=1.0,CollectionObjectRespawnSpeedRate=1.0,EnemyDropItemRate=1.0,DeathPenalty=All,bEnablePlayerToPlayerPvP=False,bEnablePalTrade=True)
PEOF
    echo "[CONFIG] Created default PalWorldSettings.ini"
fi

# Update managed fields from environment (existing custom settings are preserved)
[ -n "${SERVER_NAME}" ] && update_ini_field "${CONFIG_FILE}" "ServerName" "\"${SERVER_NAME}\""
[ -n "${SERVER_DESCRIPTION}" ] && update_ini_field "${CONFIG_FILE}" "ServerDescription" "\"${SERVER_DESCRIPTION}\""
[ -n "${ADMIN_PASSWORD}" ] && update_ini_field "${CONFIG_FILE}" "AdminPassword" "\"${ADMIN_PASSWORD}\""
[ -n "${SERVER_PASSWORD}" ] && update_ini_field "${CONFIG_FILE}" "ServerPassword" "\"${SERVER_PASSWORD}\""
[ -n "${MAX_PLAYERS}" ] && update_ini_field "${CONFIG_FILE}" "ServerPlayerMaxNum" "${MAX_PLAYERS}"
[ -n "${RCON_PORT}" ] && update_ini_field "${CONFIG_FILE}" "RCONPort" "${RCON_PORT}"
[ -n "${RCON_ENABLE}" ] && update_ini_field "${CONFIG_FILE}" "RCONEnabled" "${RCON_ENABLE}"
[ -n "${SERVER_PORT}" ] && update_ini_field "${CONFIG_FILE}" "PublicPort" "${SERVER_PORT}"
[ -n "${PUBLIC_IP}" ] && update_ini_field "${CONFIG_FILE}" "PublicIP" "\"${PUBLIC_IP}\""

echo "[CONFIG] Config fields updated"
CPARSE
chmod +x /mnt/server/config-parser.sh

# ---------- start.sh ----------
cat > /mnt/server/start.sh << 'STARTSCRIPT'
#!/bin/bash
# =============================================================================
# Palworld ARM64 — Server Startup Script
# =============================================================================
set -e

export HOME=/home/container
export FEX_ROOTFS_PATH=/home/container/.fex-emu/RootFS/
export XDG_DATA_HOME=/home/container/.local/share
export FEX_APP_DATA_LOCATION=/home/container/.fex-emu
export FEX_APP_CONFIG_LOCATION=/home/container/.fex-emu

# ---- Logging ---------------------------------------------------------------
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
    log "WARNING: RootFS appears corrupted (${ROOTFS_SIZE} bytes). Re-downloading..."
    rm -f "${FEX_ROOTFS_FILE}"
    FEXRootFSFetcher --assume-yes --as-is --distro-name Ubuntu --distro-version 22.04
    if [ $? -ne 0 ]; then
        log "ERROR: RootFS re-download failed"
        exit 1
    fi
    FEX_ROOTFS_FILE=$(find "${FEX_ROOTFS_DIR}" -name "*.sqsh" -type f 2>/dev/null | head -1)
    log "RootFS re-downloaded: $(basename "${FEX_ROOTFS_FILE}")"
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
command -v FEXInterpreter &>/dev/null || { log "FAIL: FEXInterpreter not found in PATH"; errors=$((errors+1)); }
[ -f "${HOME}/steamcmd/steamcmd.sh" ] || { log "FAIL: SteamCMD not found at ${HOME}/steamcmd/steamcmd.sh"; errors=$((errors+1)); }
[ -f "${HOME}/Pal/Binaries/Linux/PalServer-Linux-Shipping" ] || { log "FAIL: PalServer executable not found"; errors=$((errors+1)); }
[ -d "${FEX_ROOTFS_DIR}" ] && [ -n "$(ls -A "${FEX_ROOTFS_DIR}" 2>/dev/null)" ] || { log "FAIL: RootFS directory empty"; errors=$((errors+1)); }
if [ $errors -gt 0 ]; then
    log "ERROR: $errors health check(s) failed. Please re-run installation."
    exit 1
fi
log "Health check passed"

# ---- Steam SDK Fix (auto-copy steamclient.so every boot) --------------------
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

# ---- Auto Update (if enabled) -----------------------------------------------
if [ "${AUTO_UPDATE}" = "1" ]; then
    log "Auto-update enabled — checking for Palworld updates..."
    cd "${HOME}/steamcmd"
    VALIDATE_FLAG=""
    if [ "${VALIDATE}" = "1" ]; then
        VALIDATE_FLAG="validate"
        log "Validation enabled"
    fi
    FEXInterpreter ./steamcmd.sh \
        +force_install_dir "${HOME}" \
        +login anonymous \
        +app_update 2394010 ${VALIDATE_FLAG} \
        +quit
    log "Update check complete"

    # Re-copy steamclient.so after update
    cp "${HOME}/steamcmd/linux64/steamclient.so" ~/.steam/sdk64/steamclient.so 2>/dev/null || true
    cp "${HOME}/steamcmd/linux32/steamclient.so" ~/.steam/sdk32/steamclient.so 2>/dev/null || true
fi

# ---- Config Parser (create + update PalWorldSettings.ini) -------------------
bash "${HOME}/config-parser.sh"

# ---- Public IP Auto-Detection -----------------------------------------------
if [ -z "${PUBLIC_IP}" ]; then
    log "Detecting public IP..."
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
                curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
                curl -s --max-time 5 https://icanhazip.com 2>/dev/null || \
                hostname -I 2>/dev/null | awk '{print $1}' || \
                echo "127.0.0.1")
    log "Public IP detected: ${PUBLIC_IP}"
fi

# ---- RCON Helper (background) -----------------------------------------------
if [ "${RCON_ENABLE}" = "True" ]; then
    (
        while read -r cmd; do
            mcrcon -s -H "127.0.0.1" -P "${RCON_PORT}" -p "${ADMIN_PASSWORD}" "$cmd" 2>/dev/null
        done
    ) < /dev/stdin &
    log "RCON helper started on port ${RCON_PORT}"
fi

# ---- Build Server Launch Command --------------------------------------------
CMD=(FEXInterpreter "${HOME}/Pal/Binaries/Linux/PalServer-Linux-Shipping")
CMD+=("Pal")
CMD+=("-port=${SERVER_PORT}")
CMD+=("-publicport=${SERVER_PORT}")
CMD+=("-servername=${SERVER_NAME}")
CMD+=("-players=${MAX_PLAYERS}")
CMD+=("-adminpassword=${ADMIN_PASSWORD}")

if [ -n "${PUBLIC_IP}" ]; then
    CMD+=("-publicip=${PUBLIC_IP}")
fi

if [ -n "${SERVER_PASSWORD}" ]; then
    CMD+=("-serverpassword=${SERVER_PASSWORD}")
fi

if [ -n "${EXTRA_FLAGS}" ]; then
    IFS=' ' read -ra EXTRA_ARR <<< "${EXTRA_FLAGS}"
    CMD+=("${EXTRA_ARR[@]}")
fi

# ---- Signal Handling for Graceful Shutdown -----------------------------------
cleanup() {
    log "Shutdown signal received..."
    kill -TERM "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    log "Server stopped"
    exit 0
}
trap cleanup SIGTERM SIGINT

# ---- Launch Server -----------------------------------------------------------
log "Starting Palworld server..."
log "Command: ${CMD[*]}"

"${CMD[@]}" &
SERVER_PID=$!
wait $SERVER_PID
EXIT_CODE=$?

log "Server exited with code ${EXIT_CODE}"
exit ${EXIT_CODE}
STARTSCRIPT
chmod +x /mnt/server/start.sh

# =============================================================================
# Set Ownership
# =============================================================================
if id "container" &>/dev/null; then
    chown -R container:container /mnt/server
fi

# =============================================================================
# Post-Install Health Check
# =============================================================================
errors=0
command -v FEXInterpreter &>/dev/null || { log "FAIL: FEXInterpreter not found in PATH"; errors=$((errors+1)); }
[ -f /mnt/server/steamcmd/steamcmd.sh ] || { log "FAIL: SteamCMD not found"; errors=$((errors+1)); }
[ -f /mnt/server/Pal/Binaries/Linux/PalServer-Linux-Shipping ] || { log "FAIL: PalServer executable not found"; errors=$((errors+1)); }
[ -d "${FEX_ROOTFS_DIR}" ] && [ -n "$(ls -A "${FEX_ROOTFS_DIR}" 2>/dev/null)" ] || { log "FAIL: RootFS not found"; errors=$((errors+1)); }
[ -f /mnt/server/.steam/sdk64/steamclient.so ] || { log "FAIL: steamclient.so not found"; errors=$((errors+1)); }

if [ $errors -gt 0 ]; then
    log "ERROR: $errors health check(s) failed"
    exit 1
fi
log "Health check passed"

log "============================================="
log "  Installation complete!"
log "============================================="
