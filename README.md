<div align="center">

```
████████╗██████╗  █████╗ ███████╗███████╗██╗██╗  ██╗    ███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ███████╗██████╗
   ██╔══╝██╔══██╗██╔══██╗██╔════╝██╔════╝██║██║ ██╔╝    ████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗
   ██║   ██████╔╝███████║█████╗  █████╗  ██║█████╔╝     ██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗█████╗  ██████╔╝
   ██║   ██╔══██╗██╔══██║██╔══╝  ██╔══╝  ██║██╔═██╗     ██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║██╔══╝  ██╔══██╗
   ██║   ██║  ██║██║  ██║███████╗██║     ██║██║  ██╗    ██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝███████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
```

**Automatic Traefik route management for Proxmox LXC containers**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Proxmox VE](https://img.shields.io/badge/Proxmox-VE%208+-E57000?logo=proxmox&logoColor=white)](https://www.proxmox.com)
[![Node.js](https://img.shields.io/badge/Node.js-20+-339933?logo=node.js&logoColor=white)](https://nodejs.org)
[![Traefik](https://img.shields.io/badge/Traefik-v3-24A1C1?logo=traefikproxy&logoColor=white)](https://traefik.io)

</div>

---

## ✨ What is this?

**Traefik Manager** automatically creates and removes Traefik routes when you create or delete LXC containers on Proxmox VE.

Simply add a few lines in the **Notes** field of your LXC in Proxmox, and the route is created automatically — no SSH, no manual config files.

### How it works

```
LXC Notes (Proxmox UI)          Traefik Dynamic Config (auto-generated)
─────────────────────           ───────────────────────────────────────
#TRAEFIK_1_NAME=grafana    →    grafana.yourdomain.com → http://10.0.1.5:3000
#TRAEFIK_1_PORT=3000            (with SSL via Let's Encrypt)
```

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Proxmox Node                         │
│                                                             │
│  /etc/pve/lxc/105.conf ──────────────────────────────────┐  │
│  (LXC Notes with #TRAEFIK_ vars)                         │  │
│                                                          ▼  │
│  ┌──────────────────┐    inotify    ┌──────────────────┐   │
│  │  traefik-sync.sh │◄──────────────│traefik-lxc-      │   │
│  │  (sync engine)   │               │watcher.sh        │   │
│  └────────┬─────────┘               └──────────────────┘   │
│           │ pct exec                                        │
│           ▼                                                 │
│  ┌──────────────────┐    watches    ┌──────────────────┐   │
│  │  LXC Traefik     │◄──────────────│  /dynamic/*.yml  │   │
│  │  (VMID 103)      │  file reload  │  (auto-generated)│   │
│  └──────────────────┘               └──────────────────┘   │
│                                                             │
│  ┌──────────────────┐                                       │
│  │  LXC Manager     │  ← Web UI to manage everything       │
│  │  (Node.js app)   │                                       │
│  └──────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Install

### Step 1 — Install the sync engine on the Proxmox node

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/youvaKA/Lxc_Traefik_Manager/main/install-node.sh)"
```

This installs on the **Proxmox node**:
- `traefik-sync.sh` — the sync engine
- `traefik-lxc-watcher.sh` — the inotify watcher
- `traefik-lxc-sync.service` — systemd service

### Step 2 — Deploy the Web UI (optional but recommended)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/youvaKA/Lxc_Traefik_Manager/main/install-manager.sh)"
```

This creates a **dedicated LXC** with the Node.js web interface.

---

## ⚙️ Configuration

### LXC Notes syntax

In Proxmox UI → your LXC → **Notes**, add:

```bash
# Single service
#TRAEFIK_1_NAME=myapp
#TRAEFIK_1_PORT=3000

# HTTPS backend (self-signed cert)
#TRAEFIK_2_NAME=myapp-admin
#TRAEFIK_2_PORT=8443
#TRAEFIK_2_SCHEME=https

# Public access (no IP whitelist)
#TRAEFIK_3_NAME=public-api
#TRAEFIK_3_PORT=8080
#TRAEFIK_3_NOAUTH=true

# Your other notes are ignored ✓
My server notes here...
Installed on 2026-02-25
```

### Generated Traefik config (auto-created)

```yaml
# Auto-generated — LXC VMID: 105
http:
  routers:
    lxc-105-myapp:
      rule: "Host(`myapp.yourdomain.com`)"
      service: lxc-105-myapp
      entryPoints: [websecure]
      middlewares: [ip-whitelist, security-headers]
      tls:
        certResolver: letsencrypt
  services:
    lxc-105-myapp:
      loadBalancer:
        servers:
          - url: "http://10.0.1.5:3000"
        passHostHeader: true
```

### Configuration file

Edit `/usr/local/bin/traefik-sync.sh` and adjust:

```bash
BASE_DOMAIN="yourdomain.com"          # Your base domain
TRAEFIK_VMID="103"                    # VMID of your Traefik LXC
CERT_RESOLVER="letsencrypt"           # Traefik cert resolver name
HEALTH_TIMEOUT=5                      # Health check timeout (seconds)
```

---

## 📖 Manual Usage

```bash
# Sync a specific LXC
traefik-sync.sh modify 105

# Sync all LXC containers
traefik-sync.sh sync-all

# Remove routes for a LXC
traefik-sync.sh remove 105

# View status of all LXC routes
traefik-status.sh

# Watch logs
tail -f /var/log/traefik-sync.log
```

---

## 🌐 Web Interface

The web UI (installed by `install-manager.sh`) provides:

- 📋 **Dashboard** — All LXC containers with route status
- ⚙️ **Route editor** — Add/edit/remove routes via modal UI
- ▶️ **LXC control** — Start/stop containers
- ⚡ **Manual sync** — Force sync for one or all LXC
- 📡 **Live logs** — Real-time sync log stream via SSE

Access at: `https://traefik-manager.yourdomain.com`

---

## 📋 Prerequisites

### Proxmox Node
- Proxmox VE 8+
- `inotify-tools` (auto-installed)
- Access to `/etc/pve/lxc/`

### Traefik LXC
- Traefik v3+
- Provider `file` with `watch: true` in `traefik.yaml`:

```yaml
providers:
  file:
    directory: /etc/traefik/dynamic/
    watch: true
```

- A working `certResolver` named `letsencrypt` (or adjust `CERT_RESOLVER`)
- Middlewares `ip-whitelist` and `security-headers` defined in your dynamic config

### DNS
- A wildcard DNS record: `*.yourdomain.com → YOUR_PUBLIC_IP`

---

## 📁 Project Structure

```
Lxc_Traefik_Manager/
├── install-node.sh          # Install sync engine on Proxmox node
├── install-manager.sh       # Deploy Web UI LXC (tteck-style)
├── scripts/
│   ├── traefik-sync.sh      # Core sync engine
│   ├── traefik-lxc-watcher.sh  # inotify watcher
│   └── traefik-status.sh    # Status script
├── systemd/
│   └── traefik-lxc-sync.service
├── app/
│   ├── server.js            # Node.js Express backend
│   ├── package.json
│   └── public/
│       └── index.html       # Web UI
└── docs/
    └── traefik-example.yml  # Example Traefik config
```

---

## 🤝 Contributing

Contributions are welcome! Feel free to open issues and PRs.

---

## 📄 License

MIT © [youvaKA](https://github.com/youvaKA)
