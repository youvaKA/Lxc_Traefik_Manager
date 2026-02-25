#!/bin/bash
# ============================================================
# traefik-lxc-watcher.sh — inotify watcher for LXC configs
# https://github.com/youvaKA/Lxc_Traefik_Manager
# ============================================================

LXC_CONF_DIR="/etc/pve/lxc"
SYNC_SCRIPT="/usr/local/bin/traefik-sync.sh"
LOG_FILE="/var/log/traefik-sync.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WATCHER] $*" | tee -a "$LOG_FILE"; }

if ! command -v inotifywait &>/dev/null; then
    log "ERROR: inotifywait not found. Install: apt-get install inotify-tools"
    exit 1
fi

log "Starting watcher on ${LXC_CONF_DIR}"

inotifywait -m -e CREATE,MODIFY,DELETE --format '%e %f' "$LXC_CONF_DIR" 2>/dev/null | \
while read -r event file; do
    # Only process .conf files
    [[ "$file" =~ ^[0-9]+\.conf$ ]] || continue
    vmid="${file%.conf}"

    case "$event" in
        CREATE|MODIFY)
            log "Modified: LXC ${vmid}"
            "$SYNC_SCRIPT" modify "$vmid"
            ;;
        DELETE)
            log "Deleted: LXC ${vmid}"
            "$SYNC_SCRIPT" remove "$vmid"
            ;;
    esac
done
