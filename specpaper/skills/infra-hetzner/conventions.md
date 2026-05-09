# Hetzner Cloud conventions

Read this on demand. Workspace-only — do not paste into the prompt.

## Server sizing reference

| Workload | Recommended type | Why |
|---|---|---|
| Single-host stack (compose, < 50 RPS) | CCX13 | Dedicated 2 vCPU / 8 GB; ~€20/mo |
| API server (steady ~100 RPS) | CCX23 | 4 vCPU / 16 GB; headroom for spikes |
| Postgres primary | CCX33 (or larger) | 8 vCPU / 32 GB; SSD I/O matters |
| K3s control-plane node | CCX13 | Lightweight; 3 nodes for HA |
| K3s worker | CCX23+ | Application pods |
| Monitoring (Grafana + Prom + Loki) | CX31 | 2 vCPU / 8 GB; can be shared lower env |
| Dev / staging anything | CX21 / CX22 | 2 vCPU / 4 GB; shared vCPU is fine |

Rule of thumb: prod always **CCX** (dedicated vCPU). Dev / staging can be **CX**.

## Private network design

```
network: hetzner-prod (10.0.0.0/16)
├── 10.0.1.0/24  — k3s control plane
├── 10.0.2.0/24  — k3s workers
├── 10.0.3.0/24  — Postgres primary + replica
├── 10.0.4.0/24  — Caddy / load balancer
└── 10.0.10.0/24 — monitoring / observability
```

All nodes attached to the private network. **Public IPs are exposed only on Caddy / load balancer.** Everything else is reachable only via the private network or Tailscale overlay.

## Tailscale topology

- Use a **Tailscale tailnet** (or self-hosted Headscale) as the admin overlay.
- Every Hetzner node runs `tailscaled` and joins the tailnet on first boot (cloud-init).
- ACLs restrict access:
  - `team:platform` → all nodes, all ports.
  - `team:dev` → dev environment only, port 22 + 3000-9000.
  - `tag:ci` → deploy-target nodes, port 22 only, with ephemeral keys.

No public SSH on any production node. Period.

## Backup cadence

| Resource | Strategy | Cadence | Retention |
|---|---|---|---|
| Postgres | `pgbackrest` to Hetzner Storage Box | Continuous WAL archive + nightly full | 14 days nightly + 6 months monthly |
| App configs (volumes) | `restic` to Storage Box | Daily | 30 days |
| Hetzner snapshots | Cloud snapshot of OS volume | Weekly | 4 most recent |
| K3s etcd | Embedded snapshot to Storage Box | Hourly | 7 days |

Restore drills: run a documented restore on a fresh CX server **monthly**. If you can't restore, you don't have backups.

## Monitoring layout

```
monitoring host (CX31, private network only)
├── Prometheus    :9090   — scrapes all nodes via private network
├── Grafana       :3000   — UI; expose via Caddy with basic-auth or OAuth proxy
├── Loki          :3100   — log aggregation; promtail on each app node
└── Alertmanager  :9093   — routes alerts to Discord (via webhook) or email
```

Default dashboards (committed to repo):
- Node exporter overview (CPU/mem/disk/network per host).
- Postgres exporter (connections, replication lag, query rate).
- Caddy access log (RPS, latency, status codes).
- App-specific dashboards live with the app.

## Caddy patterns

- Single Caddyfile per host, in `/etc/caddy/Caddyfile`.
- Every site uses automatic HTTPS via Let's Encrypt.
- Reverse proxy to upstream services on the private network:
  ```
  api.example.com {
      reverse_proxy 10.0.2.10:8080 10.0.2.11:8080 {
          health_uri /healthz
          health_interval 10s
      }
      log {
          output file /var/log/caddy/api-access.log
          format json
      }
  }
  ```
- Avoid plugins unless necessary — vanilla Caddy build.

## Secrets management

- **SOPS + age** for files committed to the repo (`secrets/<env>/*.sops.yaml`).
- Each environment has its own age key; the deploy host has the matching private key in `/etc/sops/age.key` (root-only readable).
- Decryption happens at deploy time:
  ```
  sops --decrypt secrets/prod/app.sops.yaml > /etc/app/secrets.yaml
  ```
- For K3s: **sealed-secrets** (bitnami) — encrypted manifests committed; cluster decrypts via its own key.

## Cost discipline

- Tag servers with `project` and `env` labels (Hetzner Cloud labels).
- Hetzner doesn't have native budgeting, so a small daily cron on the monitoring host calls the Hetzner API and posts the running cost to Discord.
- Snapshot retention aggressively — old snapshots cost more than current servers if forgotten.
