# Palworld ARM64 Egg (FEX-Emu) — v3

Production-ready Pterodactyl egg for running Palworld Dedicated Server on
**Oracle Cloud Free Tier (Ampere A1 ARM64)** using FEX-Emu x86 emulation.

Zero manual fixes. Import, create, start.

> **v3 change:** Replaced dead PPA `ppa:fex-emu/fex-emu` with the official
> `ppa:fex-emu/fex` and correct package names (`fex-emu-armv8.*`).
> The old PPA no longer publishes packages.

## What This Egg Does Automatically

| Problem | How It's Fixed |
|---|---|
| SteamCMD `Exec format error` | Runs through `FEXInterpreter` |
| RootFS never downloaded | Non-interactive download via `FEXRootFSFetcher --assume-yes --as-is` |
| `GLIBCXX_3.4.29 not found` | Always uses Ubuntu 22.04 RootFS (never 20.04) |
| `HOME=/` breaks FEX | Exports `HOME=/home/container` everywhere |
| `FEX_ROOTFS_PATH` unset | Exported in Docker image + both scripts |
| `steamclient.so missing` | Auto-copied on every boot |
| `PublicIP=10.x.x.x` | Auto-detects public IP; fallback to internal |
| Config.json never created | Auto-generated targeting Ubuntu 22.04 |
| RootFS corruption | Auto-detected and re-downloaded |
| Config fields don't update | Config parser updates managed fields every boot |
| No health checks | Verifies FEXInterpreter, SteamCMD, PalServer, RootFS, steamclient.so |
| No signal handling | Traps SIGTERM/SIGINT for graceful Pterodactyl shutdown |

## Files

```
egg-palworld-arm.json     Import this into Pterodactyl
Dockerfile                Build the Docker image (multi-stage)
install.sh                Reference copy of the embedded install script
start.sh                  Reference copy of the startup script
config-parser.sh          Reference copy of the config updater
build-egg.js              Utility to regenerate the egg JSON
README.md                 This file
```

## Quick Start

### 1. Build the Docker image

```bash
# On your Oracle Cloud ARM instance (or any ARM64 host)
docker build -t palworld-arm-fex:latest .
```

Optional: push to a registry:

```bash
docker tag palworld-arm-fex:latest <your-registry>/palworld-arm-fex:latest
docker push <your-registry>/palworld-arm-fex:latest
```

If using a registry, update `docker_images` in the egg JSON.

### 2. Import the egg

1. Admin Panel > **Nests** > **Import Egg**
2. Upload `egg-palworld-arm.json`

### 3. Create a server

1. Select **Palworld ARM64 (FEX-Emu)**
2. Fill in: Server Name, Admin Password, Public IP (your Oracle public IP)
3. Allocate ports (game + RCON)
4. Create

### 4. Start

Click **Start**. First boot:

1. Downloads Ubuntu 22.04 RootFS (~1-2 GB, one-time)
2. Downloads SteamCMD (one-time)
3. Downloads Palworld via SteamCMD (~20-30 GB, one-time)
4. Copies steamclient.so
5. Generates + updates server config
6. Launches server through FEX-Emu

**Subsequent boots** skip all downloads.

## Variables

| Variable | Default | Editable | Description |
|---|---|---|---|
| `SERVER_NAME` | `A Palworld Server` | Yes | Server browser name |
| `SERVER_DESCRIPTION` | *(empty)* | Yes | Server description |
| `MAX_PLAYERS` | `32` | Yes | Max players (1-32) |
| `SERVER_PASSWORD` | *(empty)* | Yes | Join password (blank = public) |
| `ADMIN_PASSWORD` | *(required)* | Yes | Admin/RCON password |
| `PUBLIC_IP` | *(empty)* | Yes | Oracle public IP (auto-detects if blank) |
| `RCON_ENABLE` | `True` | Yes | Enable RCON |
| `RCON_PORT` | `25575` | No | RCON port |
| `AUTO_UPDATE` | `0` | Yes | Check for updates on start |
| `VALIDATE` | `0` | Yes | Force SteamCMD file validation |
| `EXTRA_FLAGS` | `-useperfthreads ...` | Yes | Extra server flags |

## Public IP (Oracle Cloud)

Oracle Cloud uses NAT. Your internal IP is `10.x.x.x` — unreachable.

**Set `PUBLIC_IP`** to your VM's public IP from the Oracle Cloud console.

If left blank, the startup script auto-detects via ipify/ifconfig.

## Configuration

Server config: `Pal/Saved/Config/LinuxServer/PalWorldSettings.ini`

- **Created** on first boot with sensible defaults
- **Updated** every boot from panel variables (ServerName, passwords, etc.)
- **Custom** settings (difficulty, rates, etc.) are preserved

Edit via Pterodactyl's File Manager for advanced settings.

## Architecture

```
Oracle Cloud ARM64 (Ampere A1)
  Docker image: ubuntu:22.04 (multi-stage build)
    Builder stage:
      PPA: ppa:fex-emu/fex (official FEX repository)
      Packages: fex-emu-armv8.{0,2,4} + fex-emu-binfmt{32,64}
      CPU auto-detection selects optimal FEX variant
      Tarball of FEX binaries + shared libs
    Runtime stage:
      squashfuse, fuse3, jq, mcrcon, curl, etc.
      FEX tarball extracted from builder
    FEX-Emu (translates x86 → ARM64)
      └── Ubuntu 22.04 x86_64 RootFS (.sqsh, squashfuse-mounted)
    SteamCMD (x86, runs under FEX)
    Palworld Server (x86, runs under FEX)
    mcrcon (ARM64 native)
```

## Migration from Old Egg

1. Back up `Pal/Saved/` via SFTP
2. Delete old server
3. Build new Docker image + import new egg
4. Create server with new egg
5. Restore `Pal/Saved/` via SFTP/file manager
6. Start

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FEX RootFS not found` | Re-run installation |
| `steamclient.so missing` | Restart (auto-copied on every boot) |
| `GLIBCXX not found` | Delete `.fex-emu/` and re-install |
| Server not visible | Set `PUBLIC_IP` to your Oracle public IP |
| `Exec format error` | Wrong architecture — rebuild with `--platform linux/arm64` |
| Slow first boot | Normal — downloading ~30 GB |
| `RootFS appears corrupted` | Automatic recovery triggers; or re-install |
| Docker build fails on PPA | Ensure you use `ppa:fex-emu/fex` (NOT `ppa:fex-emu/fex-emu`) |
| `No package fex-emu-armv8*` | PPA not added correctly; check `apt-cache policy fex-emu-armv8.0` |

## Egg Import Checklist

After import, verify:

- [ ] Startup command is `bash /home/container/start.sh`
- [ ] Installer container is `palworld-arm-fex:latest`
- [ ] 12 variables visible
- [ ] No manual startup edits needed
