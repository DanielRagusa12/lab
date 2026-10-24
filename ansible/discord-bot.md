# Discord music bot on the Mac Mini

`deploy_discord_bot.yml` deploys the application's Compose stack to the Apple Silicon `mac_mini` inventory host as `macos`. It replaces the earlier Linux-only single-container deployment. Redis is required for dashboard sessions; SQLite stores the music queue and history.

## Runtime and prerequisites

- Homebrew is owned by `daniel`. Runtime installation uses that account through sudo; it does not transfer ownership of the Homebrew prefix.
- The playbook loads `vault_mac_mini_become_password` from the existing, untracked `vault.yml`. Keep this file protected and out of Git.
- A root-owned system LaunchDaemon starts Colima as `macos` at boot. Deployment requires the existing sudo credential, but startup requires neither a GUI session nor auto-login.
- Colima uses a dedicated `music-bot` profile, the native Apple Virtualization framework, 2 CPUs, 4 GiB RAM, and a 40 GiB data disk. Kubernetes, Rosetta, foreign-architecture registration, SSH-agent forwarding, and automatic context activation are disabled.
- Only the deployment directory is shared into the VM, read-only. The rest of the user's home is not shared by this profile. Build contexts are sent through the Docker API; SQLite and Redis use named volumes inside the VM.
- Docker commands must select `--context colima-music-bot`; do not rely on the default context.

Reviewed Homebrew core bottles are Colima 0.10.3, Lima 2.2.1, Docker CLI 29.9.2, Compose 5.6.1, and Buildx 0.38.1 for `arm64_golden_gate`. Formula sources, upstream repositories, installation behavior, and bottle hashes were reviewed. The playbook checks exact formula and bottle hashes before installation, forces prebuilt bottles, disables automatic Homebrew updates/upgrades and cleanup, and uses a separate metadata cache. It does not trust unrelated taps. Lima 2.2.1 is newer than the 2.1.3 fix for CVE-2026-53657; the chosen `vz` backend is also outside that advisory's affected QEMU path. This review is not a complete security audit.

Colima 0.10.3 embeds the Docker VM image from `abiosoft/colima-core` v0.10.4, `ubuntu-24.04-minimal-cloudimg-arm64-docker.raw.gz`, with SHA-512 `32242674b046b5057e60c4aba334b51e3665f05412cda89ed081cc2de153ae5c41f6b105b5c442cbe48d78e2cc21e9ba1950e406b6fb4fc2fd1dd2259240abbd`. The default image downloader validates the embedded digest. The application also pins its Node base image, yt-dlp release/checksums for both supported architectures, and the existing Redis 7.4.7 multi-architecture image digest.

## Deploy

From this repository's `ansible/` directory:

```sh
ansible-playbook -i inventory.yml deploy_discord_bot.yml \
  -e local_bot_root=/absolute/path/to/mr-play-your-song
```

The application checkout must include its private `.env`. Pass `local_bot_root` explicitly, since older local vault files may still define a stale checkout path. Source and environment existence are checked before installing anything.

For a first-time runtime installation, add `-e bot_install_runtime=true`. If Homebrew's reviewed formula or bottle metadata has changed, installation stops for another review. Ordinary deployments do not install or upgrade host tools.

The playbook syncs source without `.git`, `.pi`, `.env*`, or `node_modules`, preserves SSH host verification, copies `.env` separately with mode 0600, builds and tests a native ARM64 image without credentials mounted into the build, starts healthy Redis, recreates the bot using the newly built image, and checks HTTP health. It does not delete persistent volumes. The SQLite source build was explicitly approved for this application; other automatic npm hooks remain disabled.

For staging before a data migration, add `-e bot_start=false`. This builds the image and skips explicit container deployment. Runtime installation or startup-definition changes can still restart the dedicated VM and its existing containers. Do not run the ordinary deployment command on a second host with the same Discord token while the first bot is still running.

The profile configuration is seeded once because Colima expands and rewrites it itself. Later VM sizing or mount changes require direct review and an intentional profile restart. Changes to the LaunchDaemon definition cause a graceful restart of this dedicated VM during deployment.

## Dashboard access

The existing `.env` uses `http://localhost:8000` for the dashboard and Discord OAuth callback. Preserve that URL with a tunnel from the workstation:

```sh
ssh -i ~/.ssh/proxmox -N -L 8000:127.0.0.1:8000 macos@192.168.1.20
```

Then open `http://localhost:8000`. Workstation port 8000 must be free. For direct LAN login, register the new callback URL in the Discord developer portal and update `APP_BASE_URL` and `DISCORD_REDIRECT_URI` together before redeploying. Do not switch only one side.

## Startup and operations

The system LaunchDaemon `/Library/LaunchDaemons/net.homelab.music-bot.colima.plist` runs Colima in the foreground as `macos` and starts it **at system boot, before user login**. The file is owned by `root:wheel` with mode 0644; the workload does not run as root on macOS. The previous per-user LaunchAgent is unloaded and removed to prevent competing supervisors.

No auto-login or FileVault changes are made. FileVault-encrypted boot volumes still require unlocking before services can start. Docker's `unless-stopped` policies restart existing service containers when the VM returns. Never delete the Colima profile as a restart operation; its disk contains the named volumes.

On the Mini:

```sh
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
cd ~/music-bot
docker --context colima-music-bot compose --project-name mr-play-your-song ps
docker --context colima-music-bot compose --project-name mr-play-your-song logs --tail 100 bot
curl --fail http://127.0.0.1:8000/health
```

Colima startup logs are under `~/Library/Logs/music-bot/`. Inspect the system job with `launchctl print system/net.homelab.music-bot.colima`. If the profile is already running independently, stop it gracefully before bootstrapping the foreground daemon. Its `start --foreground` command cannot attach to an already-running VM; the playbook rejects this state rather than creating a restart loop.

The handover and an approved server reboot verified system-domain startup, container recovery, and SQLite integrity. HTTP health recovered before any post-boot SSH connection. The Mini's pre-existing automatic login for `macos` was left enabled, so this proves unattended recovery but not startup with the Mac left at the login window. Testing that mode requires separate approval to temporarily disable automatic login. The deployment playbook itself does not reboot the server.

## Migration and rollback

Stop the source bot and Redis before the final data export. Copy the entire SQLite data directory, including any WAL files, and the entire Redis data directory, including its append-only manifest and segments. Copy them into the target's stopped containers before starting either service. Do not copy a live SQLite main file alone, or restore Redis keys without preserving their expiry times.

The initial migration verified SQLite integrity and row counts, Redis key counts, the ARM64 runtime tests, the dashboard health endpoint, and a real Discord voice connection. The voice probe joined and left without playing a song. Full song playback still needs user confirmation; upstream age restrictions and DRM are not bypassed.

The controller retains an offline snapshot under `~/.local/state/mr-play-your-song/backups/pre-colima-*`. The original workstation containers and volumes were stopped, not removed. For rollback, first stop the Mac bot and verify it is stopped, then restart the workstation stack. Its data is frozen at cutover; changes made on the Mac after cutover require a separate reverse migration if they must be retained. Never start both bot instances at once.
