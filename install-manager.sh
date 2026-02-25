#!/usr/bin/env bash
# ============================================================
# Traefik Manager — Web UI LXC Install Script
# Creates a dedicated LXC with the Node.js web interface
# https://github.com/youvaKA/Lxc_Traefik_Manager
# ============================================================

REPO="https://raw.githubusercontent.com/youvaKA/Lxc_Traefik_Manager/main"

RD=$(echo "\033[01;31m"); YW=$(echo "\033[33m"); GN=$(echo "\033[1;92m")
BL=$(echo "\033[36m"); CL=$(echo "\033[m"); BFR="\\r\\033[K"
CM="${GN}✓${CL}"; CROSS="${RD}✗${CL}"; INFO="${BL}ℹ${CL}"; HOLD=" - "

msg_info()  { echo -ne " ${HOLD} ${YW}${1}...${CL}"; }
msg_ok()    { echo -e "${BFR} ${CM} ${GN}${1}${CL}"; }
msg_error() { echo -e "${BFR} ${CROSS} ${RD}${1}${CL}"; }
msg_info2() { echo -e " ${INFO} ${BL}${1}${CL}"; }

header_info() {
  clear
  cat << "EOF"

  ████████╗██████╗  █████╗ ███████╗███████╗██╗██╗  ██╗
     ██╔══╝██╔══██╗██╔══██╗██╔════╝██╔════╝██║██║ ██╔╝
     ██║   ██████╔╝███████║█████╗  █████╗  ██║█████╔╝ 
     ██║   ██╔══██╗██╔══██║██╔══╝  ██╔══╝  ██║██╔═██╗ 
     ██║   ██║  ██║██║  ██║███████╗██║     ██║██║  ██╗
     ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝
        ███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ███████╗██████╗
        ████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗
        ██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗█████╗  ██████╔╝
        ██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║██╔══╝  ██╔══██╗
        ██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝███████╗██║  ██║
        ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
                           WEB UI — LXC Installer
EOF
  echo ""
}

catch_errors() {
  set -Eeuo pipefail
  trap 'cleanup_on_error' ERR
}

cleanup_on_error() {
  echo -e "${BFR} ${CROSS} ${RD}Une erreur est survenue. Nettoyage...${CL}"
  if [ -n "${CTID:-}" ] && pct status "$CTID" &>/dev/null 2>&1; then
    pct stop "$CTID" &>/dev/null || true
    pct destroy "$CTID" &>/dev/null || true
    echo -e " ${CROSS} ${RD}LXC ${CTID} supprimé${CL}"
  fi
  exit 1
}

# ── Valeurs par défaut ───────────────────────────────────────
CTID=$(pvesh get /cluster/nextid)
HOSTNAME="traefik-manager"
DISK="4"
CPU="1"
RAM="512"
BRIDGE="vmbr2"
IP="dhcp"
GW=""
PORT="3000"
TRAEFIK_VMID="103"
BASE_DOMAIN=""
UNPRIVILEGED="0"  # Privilégié par défaut (nécessaire pour pct)

# ── Sélection template Debian ────────────────────────────────
get_template() {
  local tmpl
  tmpl=$(pveam list local 2>/dev/null | grep "debian-12-standard" | sort -V | tail -1 | awk '{print $1}')
  if [ -z "$tmpl" ]; then
    msg_info "Téléchargement du template Debian 12 standard"
    pveam update &>/dev/null
    local avail
    avail=$(pveam available --section system | grep "debian-12-standard" | sort -V | tail -1 | awk '{print $1}')
    pveam download local "$avail" &>/dev/null
    tmpl=$(pveam list local | grep "debian-12-standard" | sort -V | tail -1 | awk '{print $1}')
  fi
  echo "$tmpl"
}

# ── Mode Simple / Avancé ─────────────────────────────────────
variables() {
  # Lecture config existante si install-node.sh déjà fait
  if [ -f /usr/local/bin/traefik-sync.sh ]; then
    TRAEFIK_VMID=$(grep 'TRAEFIK_VMID=' /usr/local/bin/traefik-sync.sh | head -1 | cut -d'"' -f2)
    BASE_DOMAIN=$(grep 'BASE_DOMAIN=' /usr/local/bin/traefik-sync.sh | head -1 | cut -d'"' -f2)
    msg_info2 "Config détectée depuis traefik-sync.sh : VMID=${TRAEFIK_VMID}, Domain=${BASE_DOMAIN}"
  fi

  if whiptail --backtitle "Traefik Manager - Web UI" \
    --title "MODE D'INSTALLATION" \
    --yesno "Utiliser les paramètres par défaut ?\n\n  CT ID      : ${CTID}\n  Hostname   : ${HOSTNAME}\n  IP         : ${IP}\n  RAM        : ${RAM} Mo\n  Disk       : ${DISK} Go\n  Port       : ${PORT}\n  Traefik ID : ${TRAEFIK_VMID}\n  Domaine    : ${BASE_DOMAIN:-À configurer}" \
    20 62; then
    # Mode simple — juste les essentiels si manquants
    if [ -z "$BASE_DOMAIN" ]; then
      BASE_DOMAIN=$(whiptail --backtitle "Traefik Manager - Web UI" \
        --title "DOMAINE REQUIS" \
        --inputbox "Entrez votre domaine de base :" 8 58 "" 3>&1 1>&2 2>&3) || exit 1
    fi
    msg_info2 "Mode Simple — paramètres par défaut"
  else
    # Mode avancé
    CTID=$(whiptail --backtitle "Traefik Manager - Web UI" --title "CT ID" \
      --inputbox "CT ID :" 8 58 "$CTID" 3>&1 1>&2 2>&3) || exit 1

    HOSTNAME=$(whiptail --backtitle "Traefik Manager - Web UI" --title "HOSTNAME" \
      --inputbox "Hostname :" 8 58 "$HOSTNAME" 3>&1 1>&2 2>&3) || exit 1

    if whiptail --backtitle "Traefik Manager - Web UI" --title "IP" \
      --yesno "Utiliser DHCP ?" 8 40; then
      IP="dhcp"; GW=""
    else
      IP=$(whiptail --backtitle "Traefik Manager - Web UI" --title "IP (CIDR)" \
        --inputbox "Adresse IP :" 8 58 "10.0.1.14/24" 3>&1 1>&2 2>&3) || exit 1
      GW=$(whiptail --backtitle "Traefik Manager - Web UI" --title "GATEWAY" \
        --inputbox "Passerelle :" 8 58 "10.0.1.1" 3>&1 1>&2 2>&3) || exit 1
    fi

    RAM=$(whiptail --backtitle "Traefik Manager - Web UI" --title "RAM (Mo)" \
      --inputbox "RAM en Mo :" 8 58 "$RAM" 3>&1 1>&2 2>&3) || exit 1

    DISK=$(whiptail --backtitle "Traefik Manager - Web UI" --title "DISQUE (Go)" \
      --inputbox "Disque en Go :" 8 58 "$DISK" 3>&1 1>&2 2>&3) || exit 1

    CPU=$(whiptail --backtitle "Traefik Manager - Web UI" --title "CPU" \
      --inputbox "Cœurs CPU :" 8 58 "$CPU" 3>&1 1>&2 2>&3) || exit 1

    BRIDGE=$(whiptail --backtitle "Traefik Manager - Web UI" --title "BRIDGE" \
      --inputbox "Bridge réseau :" 8 58 "$BRIDGE" 3>&1 1>&2 2>&3) || exit 1

    PORT=$(whiptail --backtitle "Traefik Manager - Web UI" --title "PORT" \
      --inputbox "Port de l'interface :" 8 58 "$PORT" 3>&1 1>&2 2>&3) || exit 1

    TRAEFIK_VMID=$(whiptail --backtitle "Traefik Manager - Web UI" --title "TRAEFIK VMID" \
      --inputbox "VMID du LXC Traefik :" 8 58 "$TRAEFIK_VMID" 3>&1 1>&2 2>&3) || exit 1

    BASE_DOMAIN=$(whiptail --backtitle "Traefik Manager - Web UI" --title "DOMAINE" \
      --inputbox "Domaine de base :" 8 58 "${BASE_DOMAIN:-yourdomain.com}" 3>&1 1>&2 2>&3) || exit 1
  fi

  # Résumé final
  local net_str="$IP"
  [ "$IP" != "dhcp" ] && [ -n "$GW" ] && net_str="${IP} (gw: ${GW})"

  whiptail --backtitle "Traefik Manager - Web UI" \
    --title "CONFIRMER L'INSTALLATION" \
    --yesno "Prêt à créer le LXC ?\n\n  CT ID      : ${CTID}\n  Hostname   : ${HOSTNAME}\n  Réseau     : ${net_str}\n  RAM        : ${RAM} Mo\n  Disque     : ${DISK} Go\n  CPU        : ${CPU} cœur(s)\n  Bridge     : ${BRIDGE}\n  Port app   : ${PORT}\n  Traefik ID : ${TRAEFIK_VMID}\n  Domaine    : ${BASE_DOMAIN}" \
    22 62 || { msg_error "Installation annulée"; exit 1; }
}

# ── Création du LXC ──────────────────────────────────────────
build_container() {
  msg_info "Recherche du template Debian 12"
  local template
  template=$(get_template)
  msg_ok "Template : ${template}"

  msg_info "Création du LXC ${CTID} (${HOSTNAME})"
  local net_opt="name=eth0,bridge=${BRIDGE},firewall=1"
  if [ "$IP" = "dhcp" ]; then
    net_opt="${net_opt},ip=dhcp"
  else
    net_opt="${net_opt},ip=${IP}"
    [ -n "$GW" ] && net_opt="${net_opt},gw=${GW}"
  fi

  pct create "$CTID" "$template" \
    --hostname "$HOSTNAME" \
    --cores "$CPU" \
    --memory "$RAM" \
    --net0 "$net_opt" \
    --rootfs "local:${DISK}" \
    --unprivileged "$UNPRIVILEGED" \
    --features "nesting=1" \
    --ostype debian \
    --nameserver "1.1.1.1" \
    --start 1 &>/dev/null
  sleep 4
  msg_ok "LXC ${CTID} créé et démarré"

  msg_info "Configuration des bind mounts"
  pct set "$CTID" --mp0 /etc/pve/lxc,mp=/etc/pve/lxc &>/dev/null
  [ -f /usr/local/bin/traefik-sync.sh ] && \
    pct set "$CTID" --mp1 /usr/local/bin/traefik-sync.sh,mp=/usr/local/bin/traefik-sync.sh,ro=1 &>/dev/null
  touch /var/log/traefik-sync.log
  pct set "$CTID" --mp2 /var/log/traefik-sync.log,mp=/var/log/traefik-sync.log &>/dev/null
  pct stop "$CTID" &>/dev/null && sleep 2 && pct start "$CTID" &>/dev/null && sleep 4
  msg_ok "Bind mounts configurés"
}

# ── Installation de l'app ─────────────────────────────────────
install_app() {
  msg_info "Mise à jour des paquets"
  pct exec "$CTID" -- bash -c "apt-get update -qq && apt-get upgrade -y -qq" &>/dev/null
  msg_ok "Paquets mis à jour"

  msg_info "Installation de Node.js 20"
  pct exec "$CTID" -- bash -c "
    apt-get install -y -qq curl ca-certificates &>/dev/null
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &>/dev/null
    apt-get install -y -qq nodejs &>/dev/null
  " &>/dev/null
  local node_ver
  node_ver=$(pct exec "$CTID" -- node --version 2>/dev/null || echo "installed")
  msg_ok "Node.js ${node_ver} installé"

  msg_info "Déploiement de l'application"
  pct exec "$CTID" -- mkdir -p /opt/traefik-manager/public &>/dev/null

  # server.js
  curl -fsSL "${REPO}/app/server.js" | \
    sed "s|TRAEFIK_VMID_PLACEHOLDER|${TRAEFIK_VMID}|g" | \
    sed "s|BASE_DOMAIN_PLACEHOLDER|${BASE_DOMAIN}|g" | \
    sed "s|PORT_PLACEHOLDER|${PORT}|g" | \
    pct exec "$CTID" -- bash -c "cat > /opt/traefik-manager/server.js"

  # package.json
  curl -fsSL "${REPO}/app/package.json" | \
    pct exec "$CTID" -- bash -c "cat > /opt/traefik-manager/package.json"

  # index.html
  curl -fsSL "${REPO}/app/public/index.html" | \
    pct exec "$CTID" -- bash -c "cat > /opt/traefik-manager/public/index.html"

  pct exec "$CTID" -- bash -c "cd /opt/traefik-manager && npm install --production -q" &>/dev/null
  msg_ok "Application déployée"

  msg_info "Démarrage du service"
  pct exec "$CTID" -- bash -c 'cat > /etc/systemd/system/traefik-manager.service << EOF
[Unit]
Description=Traefik Manager Web UI
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/traefik-manager
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now traefik-manager' &>/dev/null
  msg_ok "Service traefik-manager démarré"
}

# ── Route Traefik automatique ─────────────────────────────────
setup_traefik_route() {
  msg_info "Création de la route Traefik"
  local conf="/etc/pve/lxc/${CTID}.conf"
  sed -i '/^#TRAEFIK_/d' "$conf" 2>/dev/null || true
  sed -i "1i #TRAEFIK_1_NAME=traefik-manager\n#TRAEFIK_1_PORT=${PORT}" "$conf"
  if command -v traefik-sync.sh &>/dev/null; then
    traefik-sync.sh modify "$CTID" &>/dev/null || true
  fi
  msg_ok "Route → traefik-manager.${BASE_DOMAIN}"
}

# ── Résumé ────────────────────────────────────────────────────
summary() {
  local ip_display="$IP"
  if [ "$IP" = "dhcp" ]; then
    ip_display=$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "voir DHCP")
  else
    ip_display="${IP%%/*}"
  fi

  echo ""
  echo -e "  ${GN}╔══════════════════════════════════════════╗${CL}"
  echo -e "  ${GN}║     WEB UI LXC - INSTALLATION OK  ✓     ║${CL}"
  echo -e "  ${GN}╚══════════════════════════════════════════╝${CL}"
  echo ""
  echo -e "  ${CM} ${GN}Interface locale  : ${BL}http://${ip_display}:${PORT}${CL}"
  echo -e "  ${CM} ${GN}Interface Traefik : ${BL}https://traefik-manager.${BASE_DOMAIN}${CL}"
  echo ""
  echo -e "  ${INFO} ${YW}CT ID    : ${CTID}${CL}"
  echo -e "  ${INFO} ${YW}Hostname : ${HOSTNAME}${CL}"
  echo ""
  echo -e "  ${YW}Logs : pct exec ${CTID} -- journalctl -u traefik-manager -f${CL}"
  echo ""
}

# ── Main ─────────────────────────────────────────────────────
header_info
catch_errors
variables
build_container
install_app
setup_traefik_route
summary
