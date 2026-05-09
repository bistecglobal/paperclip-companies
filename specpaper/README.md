# SpecPaper

> Token-economical, spec-driven agent company for Paperclip. Eight agents that take a feature from idea to production through a disciplined propose → plan → brainstorm → build → audit → archive lifecycle.

## What it is

SpecPaper is an [Agent Companies](https://agentcompanies.io/specification) package that imports into [Paperclip](https://github.com/paperclipai/paperclip). It ports the lifecycle from [SpecClaw](https://github.com/chan4lk/specclaw) and the brainstorming techniques from [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD), then wires them into Paperclip's heartbeat / issue / approval / cost-tracking machinery.

**Tech stack focus:** .NET (C# / ASP.NET / EF Core / xUnit), Next.js (TS / React / Tailwind / Playwright), Postgres. Routing rules are tuned for these stacks; adding new specialists (Python, Go, Rust, …) is a 4-step pattern documented below.

**Deployment focus:** Azure (Bicep, App Service / AKS, Postgres Flexible, Key Vault, App Insights) and Hetzner Cloud (Terraform with `hcloud` provider, K3s / Docker Compose, Caddy, Hetzner DNS). The `enterprise-azure` and `prefer-oss` principles drive the choice.

## Org chart

```
                                CEO
                                 │
                                 ▼
                                CTO
                                 │
   ┌──────────┬──────────┬───────┼─────────┬──────────┬──────────────┐
   ▼          ▼          ▼       ▼         ▼          ▼              ▼
builder-   builder-   builder  devops   verifier  e2e-tester    (future
dotnet     nextjs    (general)                                  specialists)
```

| Agent | Role |
|---|---|
| **CEO** | Project bootstrap (clone repo, create Paperclip project, create Discord channel), business principles, escalations |
| **CTO** | Spec lifecycle: propose, plan, brainstorm, route builds, orchestrate audits, archive |
| **builder-dotnet** | One .NET / C# task per heartbeat |
| **builder-nextjs** | One Next.js / React / TS task per heartbeat |
| **builder** (generalist) | Postgres migrations, scripts, configs, docs, polyglot |
| **devops** | Bicep / Terraform / Dockerfiles / pipelines / K8s / runbooks (Azure + Hetzner) |
| **verifier** | Static spec + principles audit; produces `verify-report.md` |
| **e2e-tester** | Dynamic spec audit via Playwright against the locally hosted stack; produces `e2e-report.md` |

## Quick install

This company depends on a forked Discord plugin that adds `create_channel` and `discord_post` tools.

### 1. Install the Discord plugin (forked)

```bash
curl -X POST http://127.0.0.1:3100/api/plugins/install \
  -H "Content-Type: application/json" \
  -d '{"packageName":"git+https://github.com/bistecglobal/paperclip-plugin-discord.git"}'
```

Configure it via the Paperclip plugin settings — set `discordBotTokenRef`, `defaultGuildId`, `defaultChannelId`. The bot must have these permissions in your guild: `Send Messages`, `Manage Channels`, `Use Slash Commands`, `Read Message History`, `Embed Links`, `Add Reactions`.

### 2. Import the company

```bash
paperclipai company import --from /path/to/specpaper
```

Or use the dry-run flag first to preview:

```bash
paperclipai company import --from /path/to/specpaper --dry-run
```

### 3. Configure secrets

In Paperclip Settings → Secrets, create at minimum:

| Secret name | Required | Holds | Used by |
|---|---|---|---|
| `anthropic_api_key` | yes | Anthropic API key | All agents (default provider) |
| `discord_guild_id` | yes | Your Discord server ID | CEO bootstrap |
| `discord_projects_category_id` | yes | Discord category ID for project channels | CEO bootstrap |
| `minimax_api_key` | optional | Minimax API key (Anthropic-compatible endpoint) | Builders, only after opting in |
| `azure_devops_pat` | per-project | Azure DevOps PAT | tracker-sync.sh on AzDo projects |
| `github_token` | per-project | GitHub token | tracker-sync.sh on GitHub projects |

**All agents default to Anthropic direct.** Minimax routing is opt-in via a script after import (see [Cost optimization](#cost-optimization-minimax-routing)).

## Usage

### Bootstrap a project

In your Paperclip company's `defaultChannelId` (Discord), tell the CEO:

> @CEO Start a new project. Repo: `https://dev.azure.com/acme/payments/_git/checkout-api`. Customer: enterprise tier. Working name: Checkout API rewrite.

The CEO will:
1. Clone the repo
2. Create a Paperclip project
3. Create a Discord channel `#project-checkout-api` (via the forked plugin's `create_channel`)
4. Wire it via `/clip connect-channel project:checkout-api`
5. Register `!propose`, `!plan`, `!build`, `!verify`, `!archive`, `!status`, `!brainstorm` commands
6. Hand off to the CTO for the first feature request

### Drive a change from Discord

In the project channel:

```
!propose Add idempotency-key support to the checkout endpoint
!brainstorm idempotent-checkout                # optional, when scope is unclear
!plan idempotent-checkout
!build idempotent-checkout
!verify idempotent-checkout                     # auto-runs verifier + e2e-tester in parallel
!archive idempotent-checkout                    # if both audits pass
!status                                         # dashboard at any time
```

Each command wakes the relevant agent. Progress, approvals, and escalations show up in the channel as embeds.

## Lifecycle

```
propose ─► (brainstorm) ─► plan ─► build ─► audit (verifier ∥ e2e-tester) ─► archive
                                                       │
                                                       └─► remediation ─► build (loop)
```

Each stage writes to `.specpaper/changes/<change>/` in the workspace (agent-facing) and mirrors the human-readable subset to `<repo>/docs/changes/<change>/` (committed alongside the feature PR).

## Routing

The CTO routes build tasks by glob match in `.specpaper/config.yaml`:

```yaml
routing:
  rules:
    - match: "**/*.{cs,csproj,sln}"
      agent: builder-dotnet
    - match: "apps/web/**/*.{ts,tsx,css}"
      agent: builder-nextjs
    - match: "{**/*.bicep,**/*.tf,infra/**/*,**/Dockerfile,.github/workflows/**,azure-pipelines*.yml,**/k8s/**,**/Caddyfile}"
      agent: devops
    - match: "db/migrations/**/*.sql"
      agent: builder
    - match: "**/*"
      agent: builder
```

Tasks can also explicitly set `Agent:` in `tasks.md` to override.

## Principles

The CEO ratifies business principles per project (in `COMPANY.md` defaults and `.specpaper/changes/<c>/context.yaml` overrides). The CTO must cite applicable principles in every `design.md`:

```markdown
## Principles applied
- [x] **prefer-oss** — using PostgreSQL OSS instead of Cosmos DB
- [x] **enterprise-azure** — deploying to Azure App Service (customer is enterprise tier)
  - Conflict resolved with prefer-oss for the database choice; pre-sales accepted self-hosted Postgres
- [ ] **minimize-vendor-lock** — N/A; no vendor SDKs introduced
```

The verifier audits this section against the diff.

## Cost optimization (Minimax routing)

All agents default to **Anthropic direct**. Minimax routing is **opt-in** for builders so the company imports cleanly without requiring the `minimax_api_key` secret up front.

### Workflow

1. **Validate Minimax compatibility** with the pre-flight test:
   ```bash
   bash skills/specpaper/scripts/llm-pricing-probe.sh <change-name>
   ```
   Runs a deterministic 5-task synthetic build through both providers and compares cost + failure rate. See `DESIGN.md` for the caveat list (prompt-cache compatibility, stream-JSON parsing, `--resume` semantics).

2. **Create the `minimax_api_key` secret** in Paperclip Settings → Secrets.

3. **Opt the builders in:**
   ```bash
   # Opt in all three builders at once
   bash skills/specpaper/scripts/configure-llm-routing.sh enable-minimax --all-builders

   # Or one at a time
   bash skills/specpaper/scripts/configure-llm-routing.sh enable-minimax builder-dotnet
   ```

   The script verifies `minimax_api_key` exists in Paperclip *before* patching the agent configs. If the secret is missing, it errors with instructions and changes nothing.

4. **Inspect the current routing:**
   ```bash
   bash skills/specpaper/scripts/configure-llm-routing.sh status
   ```

5. **Revert to Anthropic direct** if the probe regresses or you change your mind:
   ```bash
   bash skills/specpaper/scripts/configure-llm-routing.sh disable-minimax --all-builders
   ```

### Recommended routing matrix

| Agent | Default | Opt-in option |
|---|---|---|
| CEO, CTO, devops, verifier, e2e-tester | Anthropic direct (Sonnet / Opus) | — |
| builder, builder-dotnet, builder-nextjs | Anthropic direct (Sonnet) | Minimax (Haiku-class) for cost |

## Adding a new specialist

To add e.g. Python support:

1. `mkdir skills/lang-python && write SKILL.md` (idiom rules, error conventions, quality gates)
2. `mkdir agents/builder-python && write AGENTS.md` (`skills: [specpaper, lang-python, paperclip]`)
3. Add a routing rule to `.specpaper/config.yaml`: `{ match: "**/*.py", agent: builder-python }`
4. Re-import the company; the new agent + skill are picked up

Same pattern works for Go, Rust, Java, Terraform-as-a-specialty, etc.

## Layout

```
specpaper/
├── COMPANY.md                # company metadata + principles + plugin requires
├── README.md                 # this file
├── LICENSE
├── DESIGN.md                 # full design rationale (kept for review history)
├── agents/                   # 8 agents, each with AGENTS.md
└── skills/                   # 7 skills (lifecycle, brainstorm, 2 langs, 2 infras, e2e)
```

## Provenance

- **Lifecycle skeleton** — ported from [SpecClaw](https://github.com/chan4lk/specclaw) (MIT). Adapted to Paperclip's heartbeat / issue / approval primitives.
- **Brainstorming techniques** — `brain-methods.csv` ported verbatim from [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) `bmad-brainstorming` skill (MIT). Workflow distilled from BMAD's 4-stage micro-files into a single focused SKILL.md.
- **Discord integration** — depends on [bistecglobal/paperclip-plugin-discord](https://github.com/bistecglobal/paperclip-plugin-discord), forked from [paperclipai/paperclip-plugin-discord](https://github.com/paperclipai/paperclip-plugin-discord) (MIT) with two added tools (`create_channel`, `discord_post`).

## License

MIT © 2026 Bistec Global
