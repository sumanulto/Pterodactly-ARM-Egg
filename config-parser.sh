#!/bin/bash
# =============================================================================
# Palworld ARM64 — Config Parser
# Creates PalWorldSettings.ini on first run, then updates managed fields
# from environment variables on every boot. Custom settings are preserved.
# Auto-created by the installation script. Reference copy.
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

# Create default config on first run
if [ ! -f "${CONFIG_FILE}" ]; then
    cat > "${CONFIG_FILE}" << 'PEOF'
[/Script/Pal.PalGameWorldSettings]
OptionSettings=(Difficulty=None,DayTimeSpeedRate=1.0,NightTimeSpeedRate=1.0,ExpRate=1.0,PalCaptureRate=1.0,PalDamageRateAttack=1.0,PalDamageRateDefense=1.0,PlayerDamageRateAttack=1.0,PlayerDamageRateDefense=1.0,PlayerStomachDecreaseRate=1.0,PlayerStaminaDecreaseRate=1.0,PlayerAutoHPRegenRate=1.0,PlayerAutoHpRegenRateInSleep=1.0,PalStomachDecreaseRate=1.0,PalAutoHPRegenRate=1.0,PalAutoHpRegenRateInSleep=1.0,BuildObjectDamageRate=1.0,BuildObjectDeteriorationDamageRate=1.0,CollectionDropRate=1.0,CollectionObjectHpRate=1.0,CollectionObjectRespawnSpeedRate=1.0,EnemyDropItemRate=1.0,DeathPenalty=All,bEnablePlayerToPlayerPvP=False,bEnablePalTrade=True)
PEOF
    echo "[CONFIG] Created default PalWorldSettings.ini"
fi

# Always update managed fields from environment variables
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
