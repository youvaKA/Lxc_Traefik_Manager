#!/usr/bin/env bash
# ============================================================
# Traefik Manager — Node Install Script
# Installs the sync engine on the Proxmox node
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
                          NODE INSTALL — Sync Engine
EOF
  echo ""
}

catch_errors() {
  set -Eeuo pipefail
  trap 'echo -e "${BFR} ${CROSS} ${RD}Error on line $LINENO${CL}"; exit 1' ERR
}

# ── Vérifications préalables ─────────────────────────────────
preflight_checks() {
  if ! command -v pct &>/dev/null; then
    msg_error "Ce script doit être exécuté sur un nœud Proxmox VE"
    exit 1
  fi
  if [ "$EUID" -ne 0 ]; then
    msg_error "Ce script doit être exécuté en root"
    exit 1
  fi
}

# ── Configuration interactive ────────────────────────────────
configure() {
  # TRAEFIK VMID
  TRAEFIK_VMID=$(whiptail --backtitle "Traefik Manager - Node Install" \
    --title "TRAEFIK LXC VMID" \
    --inputbox "Entrez le VMID du LXC Traefik :" 8 58 "103" 3>&1 1>&2 2>&3) || exit 1

  # Base domain
  BASE_DOMAIN=$(whiptail --backtitle "Traefik Manager - Node Install" \
    --title "DOMAINE DE BASE" \
    --inputbox "Entrez votre domaine de base :\n(ex: yourdomain.com)" 9 58 "" 3>&1 1>&2 2>&3) || exit 1
  [ -z "$BASE_DOMAIN" ] && { msg_error "Domaine requis"; exit 1; }

  # Vérification LXC Traefik
  if ! pct status "$TRAEFIK_VMID" &>/dev/null; then
    msg_error "LXC ${TRAEFIK_VMID} introuvable"
    exit 1
  fi

  # Vérification dynamic dir
  if ! pct exec "$TRAEFIK_VMID" -- ls /etc/traefik/dynamic &>/dev/null; then
    TRAEFIK_DYNAMIC=$(whiptail --backtitle "Traefik Manager - Node Install" \
      --title "DYNAMIC DIR" \
      --inputbox "Chemin du dossier dynamic Traefik :" 8 58 "/etc/traefik/dynamic" 3>&1 1>&2 2>&3) || exit 1
  else
    TRAEFIK_DYNAMIC="/etc/traefik/dynamic"
  fi

  # Résumé
  whiptail --backtitle "Traefik Manager - Node Install" \
    --title "RÉSUMÉ" \
    --yesno "Confirmer l'installation ?\n\n  Traefik LXC VMID : ${TRAEFIK_VMID}\n  Dynamic dir      : ${TRAEFIK_DYNAMIC}\n  Base domain      : ${BASE_DOMAIN}" \
    14 58 || { msg_error "Installation annulée"; exit 1; }
}

# ── Installation ─────────────────────────────────────────────
install() {
  msg_info "Installation de inotify-tools"
  apt-get install -y -qq inotify-tools &>/dev/null
  msg_ok "inotify-tools installé"

  msg_info "Téléchargement de traefik-sync.sh"
  curl -fsSL "${REPO}/scripts/traefik-sync.sh" -o /usr/local/bin/traefik-sync.sh
  # Injection de la config
  sed -i "s|BASE_DOMAIN=\".*\"|BASE_DOMAIN=\"${BASE_DOMAIN}\"|" /usr/local/bin/traefik-sync.sh
  sed -i "s|TRAEFIK_VMID=\".*\"|TRAEFIK_VMID=\"${TRAEFIK_VMID}\"|" /usr/local/bin/traefik-sync.sh
  sed -i "s|TRAEFIK_DYNAMIC_DIR=\".*\"|TRAEFIK_DYNAMIC_DIR=\"${TRAEFIK_DYNAMIC}\"|" /usr/local/bin/traefik-sync.sh
  chmod +x /usr/local/bin/traefik-sync.sh
  msg_ok "traefik-sync.sh installé"

  msg_info "Téléchargement de traefik-lxc-watcher.sh"
  curl -fsSL "${REPO}/scripts/traefik-lxc-watcher.sh" -o /usr/local/bin/traefik-lxc-watcher.sh
  chmod +x /usr/local/bin/traefik-lxc-watcher.sh
  msg_ok "traefik-lxc-watcher.sh installé"

  msg_info "Téléchargement de traefik-status.sh"
  curl -fsSL "${REPO}/scripts/traefik-status.sh" -o /usr/local/bin/traefik-status.sh
  sed -i "s|BASE_DOMAIN=\".*\"|BASE_DOMAIN=\"${BASE_DOMAIN}\"|" /usr/local/bin/traefik-status.sh
  sed -i "s|TRAEFIK_VMID=\".*\"|TRAEFIK_VMID=\"${TRAEFIK_VMID}\"|" /usr/local/bin/traefik-status.sh
  chmod +x /usr/local/bin/traefik-status.sh
  msg_ok "traefik-status.sh installé"

  msg_info "Installation du service systemd"
  curl -fsSL "${REPO}/systemd/traefik-lxc-sync.service" -o /etc/systemd/system/traefik-lxc-sync.service
  systemctl daemon-reload
  systemctl enable --now traefik-lxc-sync.service &>/dev/null
  msg_ok "Service traefik-lxc-sync démarré"

  # Créer le fichier de log
  touch /var/log/traefik-sync.log

  msg_info "Synchronisation initiale de tous les LXC"
  traefik-sync.sh sync-all &>/dev/null || true
  msg_ok "Synchronisation initiale terminée"
}

# ── Résumé final ─────────────────────────────────────────────
summary() {
  echo ""
  echo -e "  ${GN}╔══════════════════════════════════════════╗${CL}"
  echo -e "  ${GN}║     SYNC ENGINE - INSTALLATION OK  ✓    ║${CL}"
  echo -e "  ${GN}╚══════════════════════════════════════════╝${CL}"
  echo ""
  echo -e "  ${CM} ${GN}Traefik VMID : ${TRAEFIK_VMID}${CL}"
  echo -e "  ${CM} ${GN}Base domain  : ${BASE_DOMAIN}${CL}"
  echo -e "  ${CM} ${GN}Dynamic dir  : ${TRAEFIK_DYNAMIC}${CL}"
  echo ""
  echo -e "  ${YW}UTILISATION :${CL}"
  echo -e "  Dans les Notes Proxmox d'un LXC :"
  echo -e "  ${BL}  #TRAEFIK_1_NAME=monapp${CL}"
  echo -e "  ${BL}  #TRAEFIK_1_PORT=3000${CL}"
  echo ""
  echo -e "  ${YW}COMMANDES :${CL}"
  echo -e "  ${BL}  traefik-sync.sh sync-all${CL}"
  echo -e "  ${BL}  traefik-status.sh${CL}"
  echo -e "  ${BL}  tail -f /var/log/traefik-sync.log${CL}"
  echo ""
  echo -e "  ${YW}WEB UI :${CL}"
  echo -e "  ${BL}  bash -c \"\$(curl -fsSL ${REPO}/install-manager.sh)\"${CL}"
  echo ""
}

# ── Main ─────────────────────────────────────────────────────
header_info
catch_errors
preflight_checks
configure
install
summary
