#!/bin/bash
# ============================================================
# traefik-status.sh — Status of all LXC Traefik routes
# https://github.com/youvaKA/Lxc_Traefik_Manager
# ============================================================

BASE_DOMAIN="yourdomain.com"
TRAEFIK_VMID="103"
TRAEFIK_DYNAMIC_DIR="/etc/traefik/dynamic"
LXC_CONF_DIR="/etc/pve/lxc"
HEALTH_TIMEOUT=3

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

check_url() {
    local code
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time "$HEALTH_TIMEOUT" "$1" 2>/dev/null)
    echo "$code"
}

echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD} Traefik Manager — Status  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BOLD}================================================================${NC}"
printf "${BOLD}%-6s %-22s %-36s %-10s %-10s${NC}\n" "VMID" "NAME" "DOMAIN" "BACKEND" "PUBLIC"
echo "----------------------------------------------------------------"

for conf in "${LXC_CONF_DIR}"/*.conf; do
    vmid=$(basename "$conf" .conf)
    [[ "$vmid" =~ ^[0-9]+$ ]] || continue
    [ "$vmid" = "$TRAEFIK_VMID" ] && continue

    name=$(grep "^hostname:" "$conf" | cut -d' ' -f2)
    ip=$(pct exec "$vmid" -- hostname -I 2>/dev/null | awk '{print $1}' || \
         grep -oP 'ip=\K[0-9.]+' "$conf" 2>/dev/null | head -1)

    # Collect all services
    declare -a services=()
    indices=$(grep -oP "^#TRAEFIK_\K[0-9]+" "$conf" 2>/dev/null | sort -un)
    for i in $indices; do
        n=$(grep "^#TRAEFIK_${i}_NAME=" "$conf" | cut -d'=' -f2 | tr -d '[:space:]')
        p=$(grep "^#TRAEFIK_${i}_PORT=" "$conf" | cut -d'=' -f2 | tr -d '[:space:]')
        [ -n "$n" ] && [ -n "$p" ] && services+=("${n}:${p}")
    done
    # Legacy
    ln=$(grep "^#TRAEFIK_SUB_DOMAINE_NAME=" "$conf" | cut -d'=' -f2 | tr -d '[:space:]')
    lp=$(grep "^#TRAEFIK_PORT=" "$conf" | cut -d'=' -f2 | tr -d '[:space:]')
    [ -n "$ln" ] && [ -n "$lp" ] && services+=("${ln}:${lp}")

    if [ ${#services[@]} -eq 0 ]; then
        printf "%-6s ${YELLOW}%-22s${NC} %-36s\n" "$vmid" "$name" "(no traefik config)"
        continue
    fi

    for svc in "${services[@]}"; do
        IFS=':' read -r sname port <<< "$svc"
        domain="${sname}.${BASE_DOMAIN}"

        # Backend check
        bc=$(check_url "http://${ip}:${port}")
        if [ "$bc" = "000" ]; then
            bstatus="${RED}✗ DOWN${NC}"
        else
            bstatus="${GREEN}✓ ${bc}${NC}"
        fi

        # Public check
        pc=$(check_url "https://${domain}")
        if [ "$pc" = "000" ]; then
            pstatus="${RED}✗ DOWN${NC}"
        elif [[ "$pc" =~ ^[23] ]] || [ "$pc" = "401" ] || [ "$pc" = "403" ]; then
            pstatus="${GREEN}✓ ${pc}${NC}"
        else
            pstatus="${YELLOW}⚠ ${pc}${NC}"
        fi

        printf "%-6s ${CYAN}%-22s${NC} %-36s %-20b %-10b\n" \
            "$vmid" "$name" "$domain" "$bstatus" "$pstatus"
    done
    unset services
done

echo "================================================================"
echo -e "Logs: ${BOLD}tail -f /var/log/traefik-sync.log${NC}"
