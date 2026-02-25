const express = require('express');
const { exec, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 'PORT_PLACEHOLDER';

const CONFIG = {
  LXC_CONF_DIR: '/etc/pve/lxc',
  TRAEFIK_VMID: process.env.TRAEFIK_VMID || 'TRAEFIK_VMID_PLACEHOLDER',
  TRAEFIK_DYNAMIC_DIR: '/etc/traefik/dynamic',
  SYNC_SCRIPT: '/usr/local/bin/traefik-sync.sh',
  LOG_FILE: '/var/log/traefik-sync.log',
  BASE_DOMAIN: process.env.BASE_DOMAIN || 'BASE_DOMAIN_PLACEHOLDER',
};

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ── Helpers ───────────────────────────────────────────────────────────────────

function execCmd(cmd) {
  return new Promise((resolve, reject) => {
    exec(cmd, { timeout: 10000 }, (err, stdout, stderr) => {
      if (err) reject({ error: err.message, stderr });
      else resolve(stdout.trim());
    });
  });
}

function parseTraefikConfig(conf) {
  const services = [];
  const lines = conf.split('\n');

  // New format
  const indices = [...new Set(
    lines.map(l => l.match(/^#TRAEFIK_(\d+)_/)).filter(Boolean).map(m => m[1])
  )];
  for (const i of indices) {
    const name   = lines.find(l => l.startsWith(`#TRAEFIK_${i}_NAME=`))?.split('=')[1]?.trim();
    const port   = lines.find(l => l.startsWith(`#TRAEFIK_${i}_PORT=`))?.split('=')[1]?.trim();
    const scheme = lines.find(l => l.startsWith(`#TRAEFIK_${i}_SCHEME=`))?.split('=')[1]?.trim() || 'http';
    const noauth = lines.some(l => l.startsWith(`#TRAEFIK_${i}_NOAUTH=true`));
    if (name && port) services.push({ name, port, scheme: noauth ? 'noauth' : scheme, index: parseInt(i) });
  }

  // Legacy format
  const lname   = lines.find(l => l.startsWith('#TRAEFIK_SUB_DOMAINE_NAME='))?.split('=')[1]?.trim();
  const lport   = lines.find(l => l.startsWith('#TRAEFIK_PORT='))?.split('=')[1]?.trim();
  const lscheme = lines.find(l => l.startsWith('#TRAEFIK_SCHEME='))?.split('=')[1]?.trim() || 'http';
  if (lname && lport) services.push({ name: lname, port: lport, scheme: lscheme, index: 0, legacy: true });

  return services;
}

function getLxcConf(vmid) {
  const confPath = path.join(CONFIG.LXC_CONF_DIR, `${vmid}.conf`);
  if (!fs.existsSync(confPath)) return null;
  return fs.readFileSync(confPath, 'utf8');
}

// ── API Routes ────────────────────────────────────────────────────────────────

// GET /api/lxc
app.get('/api/lxc', async (req, res) => {
  try {
    const stdout = await execCmd('pct list');
    const lines = stdout.split('\n').slice(1).filter(Boolean);
    const lxcList = [];

    for (const line of lines) {
      const parts = line.trim().split(/\s+/);
      const vmid = parts[0], status = parts[1], name = parts[3] || parts[2] || '';
      if (vmid === CONFIG.TRAEFIK_VMID) continue;

      const conf = getLxcConf(vmid);
      const services = conf ? parseTraefikConfig(conf) : [];
      const routeFiles = [];

      for (const svc of services) {
        try {
          await execCmd(`pct exec ${CONFIG.TRAEFIK_VMID} -- ls ${CONFIG.TRAEFIK_DYNAMIC_DIR}/lxc-${vmid}-${svc.name}.yml`);
          routeFiles.push(`lxc-${vmid}-${svc.name}.yml`);
        } catch {}
      }
      lxcList.push({ vmid, status, name, services, routeFiles });
    }
    res.json(lxcList);
  } catch (e) { res.status(500).json({ error: e.error || e.message }); }
});

// POST /api/lxc/:vmid/start
app.post('/api/lxc/:vmid/start', async (req, res) => {
  try { await execCmd(`pct start ${req.params.vmid}`); res.json({ ok: true }); }
  catch (e) { res.status(500).json({ error: e.error || e.message }); }
});

// POST /api/lxc/:vmid/stop
app.post('/api/lxc/:vmid/stop', async (req, res) => {
  try { await execCmd(`pct stop ${req.params.vmid}`); res.json({ ok: true }); }
  catch (e) { res.status(500).json({ error: e.error || e.message }); }
});

// PUT /api/lxc/:vmid/services
app.put('/api/lxc/:vmid/services', (req, res) => {
  const { vmid } = req.params;
  const { services } = req.body;
  const confPath = path.join(CONFIG.LXC_CONF_DIR, `${vmid}.conf`);
  if (!fs.existsSync(confPath)) return res.status(404).json({ error: 'LXC not found' });

  let conf = fs.readFileSync(confPath, 'utf8');
  conf = conf.split('\n').filter(l => !l.match(/^#TRAEFIK_/)).join('\n');

  const newLines = [];
  services.forEach((svc, i) => {
    const n = i + 1;
    newLines.push(`#TRAEFIK_${n}_NAME=${svc.name}`);
    newLines.push(`#TRAEFIK_${n}_PORT=${svc.port}`);
    if (svc.scheme && svc.scheme !== 'http') newLines.push(`#TRAEFIK_${n}_SCHEME=${svc.scheme}`);
    if (svc.noauth) newLines.push(`#TRAEFIK_${n}_NOAUTH=true`);
  });

  fs.writeFileSync(confPath, newLines.join('\n') + '\n' + conf.trim());
  res.json({ ok: true });
});

// DELETE /api/lxc/:vmid/services
app.delete('/api/lxc/:vmid/services', async (req, res) => {
  const { vmid } = req.params;
  const confPath = path.join(CONFIG.LXC_CONF_DIR, `${vmid}.conf`);
  if (!fs.existsSync(confPath)) return res.status(404).json({ error: 'LXC not found' });

  let conf = fs.readFileSync(confPath, 'utf8');
  conf = conf.split('\n').filter(l => !l.match(/^#TRAEFIK_/)).join('\n');
  fs.writeFileSync(confPath, conf);

  await execCmd(`pct exec ${CONFIG.TRAEFIK_VMID} -- bash -c "rm -f ${CONFIG.TRAEFIK_DYNAMIC_DIR}/lxc-${vmid}-*.yml"`).catch(() => {});
  res.json({ ok: true });
});

// POST /api/sync
app.post('/api/sync', async (req, res) => {
  const vmid = req.body?.vmid;
  const cmd = vmid
    ? `${CONFIG.SYNC_SCRIPT} modify ${vmid}`
    : `${CONFIG.SYNC_SCRIPT} sync-all`;
  try { res.json({ ok: true, output: await execCmd(cmd) }); }
  catch (e) { res.status(500).json({ error: e.error || e.message }); }
});

// GET /api/logs (SSE)
app.get('/api/logs', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  if (fs.existsSync(CONFIG.LOG_FILE)) {
    const lines = fs.readFileSync(CONFIG.LOG_FILE, 'utf8').split('\n').filter(Boolean).slice(-50);
    for (const line of lines) res.write(`data: ${JSON.stringify({ line, historical: true })}\n\n`);
  }

  const tail = spawn('tail', ['-f', '-n', '0', CONFIG.LOG_FILE]);
  tail.stdout.on('data', data => {
    for (const line of data.toString().split('\n').filter(Boolean))
      res.write(`data: ${JSON.stringify({ line })}\n\n`);
  });
  req.on('close', () => tail.kill());
});

// GET /api/config
app.get('/api/config', (req, res) => {
  res.json({ baseDomain: CONFIG.BASE_DOMAIN, traefikVmid: CONFIG.TRAEFIK_VMID });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Traefik Manager running on http://0.0.0.0:${PORT}`);
  console.log(`Base domain: ${CONFIG.BASE_DOMAIN}`);
});
