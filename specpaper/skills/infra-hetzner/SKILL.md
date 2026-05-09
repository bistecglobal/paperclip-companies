---
name: infra-hetzner
description: "Hetzner Cloud infrastructure conventions for the SpecPaper devops agent. Active when context.deployment_target = hetzner (default for non-enterprise per the prefer-oss principle)."
---

# Hetzner Cloud conventions for SpecPaper

You provision and operate Hetzner Cloud infrastructure when `context.deployment_target = hetzner`. These conventions are the always-loaded baseline; load `conventions.md` and `snippets/*.md` for unfamiliar patterns.

## Defaults

- **IaC:** Terraform with the **`hetznercloud/hcloud`** provider for compute/network/volume/firewall/load-balancer; **`timohirt/hetznerdns`** for DNS records (or the official `hetzner/hetzner` provider when stable).
  - Backend: Hetzner Storage Box via `sftp` backend, or HTTP backend (e.g., Terraform Cloud / a self-hosted state service) — **never local state in committed repos.**
- **Compute:**
  - Production → **CCX** dedicated-vCPU servers (CCX23+ for non-trivial workloads).
  - Dev / staging → **CX** shared-vCPU.
  - OS: **Debian stable** (Ubuntu LTS acceptable if the project is already on it).
- **Orchestration, decision tree:**
  - Single-host stack → **Docker Compose** with a managed reverse proxy.
  - Multi-host or stateful with replication → **K3s** (lightweight K8s) on 3 CCX nodes.
  - Avoid Nomad / Swarm in new projects.
- **Reverse proxy / TLS:** **Caddy** with automatic Let's Encrypt. Caddyfile at repo root or in `infra/`. **No nginx** unless a project specifically needs an nginx-only feature; if so, document why in `conventions.md`.
- **Data:**
  - Postgres → dedicated server (CCX with sufficient RAM, attached volume for data dir), `pgbackrest` to a Hetzner **Storage Box** for incremental backups + WAL.
  - Cache → Redis on a CX node, or in-process for small workloads.
  - Object storage → Hetzner Storage Box (sftp / WebDAV) for backups, **MinIO** on a CCX for app object storage if needed.
- **DNS:** **Hetzner DNS** (free, fast). Records as code via the Terraform provider — **no clicks in the UI.**
- **Secrets:**
  - K3s → `sealed-secrets` (bitnami) or Mozilla SOPS+age committed encrypted.
  - Compose stacks → SOPS+age files, decrypted at deploy time on the host.
  - **Never plaintext secrets in repo.**
- **Networking:** every production stack uses a **Hetzner private network** + **Tailscale** (or wireguard) overlay for admin access. Public surface is only Caddy (80/443). Firewall rules in the Hetzner firewall, not just iptables.
- **Observability:** **Grafana + Prometheus** on a dedicated CX server, scraping over the private network. **Loki** for logs.
- **CI/CD:**
  - GitHub repo → **GitHub Actions**, deploys via SSH to the target Hetzner host.
  - Azure DevOps repo → **AzDo Pipelines**, same deploy pattern.
  - SSH auth via deploy keys (project-scoped); **no passwords**, **no shared keys.**

## Quality gates DevOps runs before commit

For every task that touches `**/*.tf` / `**/Caddyfile` / `**/Dockerfile` / `**/docker-compose*.yml`:

1. `terraform fmt -recursive` — fix in place.
2. `terraform validate` — must pass with zero errors.
3. `terraform plan` against the **dev workspace** — review the plan; **no `apply` unless the task explicitly says deploy.**
4. `caddy validate --config <Caddyfile>` if a Caddyfile is touched.
5. `docker build` smoke test for any new/modified Dockerfile.
6. `docker compose config` for any compose file (catches YAML-level errors).

## Anti-patterns to refuse

- **Local Terraform state** committed to the repo — always remote backend.
- **`hcloud_server.user_data` containing secrets** — secrets via SOPS-decrypted files post-boot, not cloud-init.
- **Public DB exposure** — Postgres listens only on the private network.
- **Single-server prod with no backup** — at minimum nightly `pgbackrest` to Storage Box, even for small projects.
- **Deploys via `scp` of zip files** — use `docker compose pull` against a registry image, or pull from git.
- **Manual Hetzner DNS record edits** — if you find drift, the task is to bring code up to date.

## Read on demand

- `./conventions.md` — server sizing reference (CX/CCX), private network design, Tailscale topology, backup cadence, monitoring layout.
- `./snippets/k3s-bootstrap.md` — the standard 3-node K3s cluster on CCX servers with sealed-secrets and Caddy.
- `./snippets/compose-stack.md` — single-host Docker Compose pattern with Caddy + app + Postgres + Watchtower.
- `./snippets/postgres-pgbackrest.md` — Postgres + pgbackrest + Storage Box restore procedure.
- `./snippets/terraform-modules.md` — reusable modules for `cluster`, `single-host`, `dns-zone`.
