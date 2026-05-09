# SpecPaper — Design Proposal

> Status: **proposal** — pending approval before any agents/skills are written.
> Target: PR to `paperclipai/companies` repo as a new top-level company directory.

## Goal

A token-economical Paperclip company that reproduces the **specclaw** lifecycle (propose → plan → build → verify → archive) and absorbs the **best of BMAD** (its brainstorming techniques, *not* its multi-step workflow boilerplate). Adds two things specclaw lacked:

1. **Tracker-agnostic sync** — works with both GitHub Issues and **Azure DevOps Work Items** behind one script.
2. **In-repo docs** — proposal/spec/design and verify report mirrored into `docs/changes/<change>/` of the project repo so humans (and Azure DevOps Wiki) can browse without touching the agent's `.specpaper/` working dir.

## Non-goals

- Re-implementing BMAD's full agent roster (PO/PM/Architect/SM/Dev/QA — too heavy for our token budget).
- Replacing Paperclip's heartbeat/governance machinery — we lean on it, not around it.
- Workspaces UI — agents work via CLI scripts and Paperclip child issues.

---

## Token-economy principles

These are the design constraints driving every choice below. Each connects to specifics in the Paperclip Claude adapter (`packages/adapters/claude-local`).

| Principle | Why it matters | How we apply it |
|---|---|---|
| **Few skills, stable bundles** | The Claude adapter hashes every skill file into a `bundleKey` (`prompt-cache.ts:86`). Any edit invalidates the cached session prefix and forces a cold start. | We ship **2 skills** (`specpaper`, `specpaper-brainstorm`). Skill files are touched rarely. Frequently-changing assets (templates, config) live under `.specpaper/`, not in skills. |
| **Lean per-agent instructions** | `combinedInstructionsContents` (`execute.ts:423`) is appended via `--append-system-prompt-file` once per fresh session. Bigger = more cold-start cost. | Each `AGENTS.md` is ~30 lines of role + behavior, not procedure. Procedure lives in the skill. |
| **Per-task fresh context, in workspace not prompt** | Stdin per heartbeat is *not* prefix-cached; every kilobyte there re-tokenizes. | `build-context.sh` writes a context file *into* the workspace (`.specpaper/changes/<c>/.task-context-<id>.md`). The Builder reads it via `Read` lazy-loaded — only the relevant files for this task land in context. |
| **Minimal wake delta** | Resume delta wake (`server-utils.ts:627`) keeps heartbeats cheap. | Builder agents never hold cross-task context. Lead delegates via child issues so each Builder pickup is naturally scoped. |
| **In-repo docs are read-on-demand** | Files in the workspace are not in the prompt prefix. The agent loads them when relevant. | All change artifacts live in `.specpaper/` and `docs/changes/`. Skills tell the agent *where to look*, not *what's there*. |

Concretely: **target ~1k token system-prompt overhead per agent** (compared to ~6-8k for BMAD-style installs), and **per-heartbeat stdin under 2k** for a Builder picking up a task.

---

## Org chart (8 agents)

```
                              ┌─────┐
                              │ CEO │  customer-facing, project bootstrap, business principles
                              └──┬──┘
                                 │ assigns project to
                              ┌──▼──┐
                              │ CTO │  spec lifecycle (propose/plan/brainstorm/verify-orchestration)
                              └──┬──┘
                                 │ delegates child issues by routing rules
        ┌──────────┬─────────┬──┼─────────┬─────────┬────────────┐
        ▼          ▼         ▼  ▼         ▼         ▼            ▼
  ┌──────────┐ ┌─────────┐ ┌───────┐ ┌────────┐ ┌────────┐ ┌────────────┐
  │ builder- │ │ builder-│ │builder│ │ devops │ │verifier│ │ e2e-tester │
  │ dotnet   │ │ nextjs  │ │(gen.) │ │        │ │(static)│ │ (dynamic)  │
  └──────────┘ └─────────┘ └───────┘ └────────┘ └────────┘ └────────────┘
```

| Agent | Owns | Why separate |
|---|---|---|
| **CEO** | Project bootstrap (clone repo, create Paperclip project, create Discord channel), customer/tier context, business principles, escalations | Customer-facing surface, rarely active. Different cadence and concerns from technical work. Holds the *business* context (`customer_tier`, deadlines) that biases CTO planning. |
| **CTO** | Propose, plan, brainstorm, verify-orchestration, archive, dashboard | Technical lead. Long-lived planning context; holds the spec lifecycle. The agent that actually runs `specpaper plan/build/verify`. |
| **builder-dotnet** | One .NET task per heartbeat | Loads the .NET conventions (C#, ASP.NET, EF Core, xUnit) without polluting Next.js builder cache. |
| **builder-nextjs** | One Next.js / React / TS task per heartbeat | Loads Next.js + React idioms, Tailwind, server actions, App Router patterns. |
| **builder** (generalist) | SQL migrations, docs, scripts, polyglot tasks | Catches everything outside .NET / Next.js / infra (Postgres migrations, README updates, ad-hoc scripts). |
| **devops** | Infrastructure-as-code, CI/CD pipelines, container images, deployment, observability | Carries `infra-azure` + `infra-hetzner` skills. The agent that turns the CTO's `context.deployment_target` choice into actual provisioned infra. Owns runbook authorship in `docs/runbooks/`. |
| **verifier** | Static spec audit: reads `spec.md`, the diff, and design.md's `Principles applied`. Produces `verify-report.md` | Adversarial *reading*. Catches what the spec promised vs what the diff actually does. |
| **e2e-tester** | Dynamic spec audit: starts the local stack, exercises user flows in a real browser, captures evidence. Produces `e2e-report.md` | Adversarial *exercising*. Carries the `e2e-playwright` skill. Catches what works on paper but breaks at runtime. Runs in parallel with verifier after the build wave. |

### Why split CEO and CTO?

- **Different concerns, different contexts.** The CEO owns *what to build, for whom, under which constraints*. The CTO owns *how it gets built*. Mixing produces a session that pivots between "discuss customer tier with the user in Discord" and "decompose tasks for Wave 3." That swing bloats the resume delta and weakens both modes.
- **Customer-facing isolation.** The CEO is the only agent users typically chat with directly in Discord. Keeping that conversational surface out of the CTO session means the CTO's prompt doesn't fill with chat noise.
- **Separation of authority.** Business principles (`prefer-oss`, `enterprise-azure`) are CEO-owned and ratified once per project. Technical principles (`minimize-vendor-lock`, language conventions) are CTO-owned and applied per change. The split mirrors the principle authorship.
- **Cost.** Both agents resume across heartbeats. CEO is mostly idle (active during bootstrap and escalations only); its per-heartbeat cost is near zero when no project events fire. CTO is the active workhorse. Net cost vs single Architect: marginal — one extra mostly-idle session.

---

## File layout

```
specpaper/
├── COMPANY.md                          # frontmatter: name, slug, schema, goals
├── README.md                           # human-facing overview + import instructions
├── LICENSE
├── DESIGN.md                           # this file (kept for PR review history)
├── agents/
│   ├── ceo/AGENTS.md                   # ~35 lines: bootstrap + business principles
│   ├── cto/AGENTS.md                   # ~35 lines: spec lifecycle, brainstorm, routing
│   ├── builder/AGENTS.md               # ~25 lines: generalist
│   ├── builder-dotnet/AGENTS.md        # ~25 lines: .NET specialist
│   ├── builder-nextjs/AGENTS.md        # ~25 lines: Next.js specialist
│   ├── devops/AGENTS.md                # ~30 lines: infra, CI/CD, deploy (Azure + Hetzner)
│   ├── verifier/AGENTS.md              # ~25 lines: static spec audit
│   └── e2e-tester/AGENTS.md            # ~30 lines: dynamic spec audit via local stack
└── skills/
    ├── specpaper/                      # core lifecycle (loaded by CEO + CTO + builders + verifier)
    │   ├── SKILL.md                    # ported from specclaw, paperclip-fied
    │   ├── templates/                  # config.yaml, project.yaml, proposal.md, spec.md, design.md, tasks.md, …
    │   └── scripts/
    │       ├── init.sh                 # ported
    │       ├── bootstrap.sh            # NEW: clone + paperclip project + discord channel + init
    │       ├── validate-change.sh      # ported
    │       ├── parse-tasks.sh          # ported (+ glob-based agent routing)
    │       ├── update-task-status.sh   # ported
    │       ├── build-context.sh        # MODIFIED: writes to .task-context-<id>.md
    │       ├── build.sh                # MODIFIED: paperclip child-issue delegation, agent routing
    │       ├── verify.sh               # ported, drops sessions_spawn
    │       ├── verify-context.sh       # ported
    │       ├── log-error.sh            # ported
    │       ├── log-learning.sh         # ported
    │       ├── detect-patterns.sh      # ported
    │       ├── update-status.sh        # ported
    │       ├── tracker-sync.sh         # NEW: github | azure-devops | none
    │       ├── docs-sync.sh             # NEW: mirrors to <repo>/docs/changes/<change>/
    │       ├── discord-sync.sh          # NEW: ~30 lines — bootstrap welcome + brainstorm summary only
    │       └── discord-register-commands.sh  # NEW: idempotently registers !propose/!plan/!build/etc
    ├── specpaper-brainstorm/           # loaded only by CTO
    │   ├── SKILL.md                    # ~150 lines: technique selection + anti-bias rules + output spec
    │   └── brain-methods.csv           # 60-row catalog ported verbatim from BMAD (MIT)
    ├── lang-dotnet/                    # loaded only by builder-dotnet
    │   ├── SKILL.md                    # ~120 lines: C#/.NET conventions + quality gates
    │   ├── conventions.md              # workspace-only: solution layout, DI, EF Core patterns
    │   └── snippets/                   # workspace-only: reference patterns read on demand
    ├── lang-nextjs/                    # loaded only by builder-nextjs
    │   ├── SKILL.md                    # ~120 lines: Next.js / TS / React conventions + quality gates
    │   ├── conventions.md              # workspace-only: app router, server actions, data fetching
    │   └── snippets/                   # workspace-only: form patterns, auth patterns, etc.
    ├── infra-azure/                    # loaded by devops; activated when context.deployment_target = azure
    │   ├── SKILL.md                    # ~140 lines: Bicep, App Service vs AKS vs Container Apps decision rules,
    │   │                               #            Key Vault for secrets, App Insights, AzDo Pipelines / GH Actions
    │   ├── conventions.md              # workspace-only: resource group structure, naming, tagging policy, RBAC
    │   └── snippets/                   # workspace-only: bicep modules, AKS bootstrap, Postgres flexible server, etc.
    ├── infra-hetzner/                  # loaded by devops; activated when context.deployment_target = hetzner
    │   ├── SKILL.md                    # ~140 lines: Hetzner Cloud + Terraform (hcloud provider), K3s / Docker Compose,
    │   │                               #            Caddy reverse proxy, Hetzner DNS, snapshot strategy
    │   ├── conventions.md              # workspace-only: server sizing (CX/CCX), volume layout, network setup
    │   └── snippets/                   # workspace-only: terraform modules, k3s bootstrap, compose stacks
    └── e2e-playwright/                 # loaded only by e2e-tester
        ├── SKILL.md                    # ~130 lines: Playwright conventions, page-object pattern, retry/flake handling,
        │                               #            local-stack lifecycle (compose up/down), evidence capture
        ├── conventions.md              # workspace-only: selector strategy, fixtures, network interception, visual regression
        └── snippets/                   # workspace-only: auth flow, form fill + submit, multi-tab, file upload patterns
```

---

## Lifecycle (mapped from specclaw to paperclip)

The skill's commands are recognized conversationally, same as specclaw, but the orchestration primitives change:

| Stage | Specclaw (OpenClaw) | SpecPaper (Paperclip) |
|---|---|---|
| Spawn coding agent | `sessions_spawn(task=…)` | `POST /api/companies/{cid}/issues` with `assigneeAgentId=builder`, `parentId=<change-issue>`, body=`<context-file path>` |
| Wait for completion | `sessions_yield` | Lead returns `in_review` on the change issue with `wake_assignee` continuation; Paperclip wakes Lead when builders close their child issues |
| Notify | `message` tool to channel | Comment on the change issue + (optional) Discord plugin if configured |
| Tracker sync | `gh-sync.sh` (GitHub only) | `tracker-sync.sh` — dispatches to `gh` or `az boards` |
| Fresh per-task context | inline in `sessions_spawn` task arg | written to `.task-context-<id>.md`, Builder reads it |

**Wave-based parallelism** still works: Lead creates N child issues for the wave, each blocked until prior-wave issues close. Paperclip's blocker dependency system gives us the wave gate for free.

**Retry flow** still works: re-running `specpaper build <change>` parses tasks marked `[!]`, resets to pending, and re-creates child issues with the previous error block included via `build-context.sh`.

---

## Scaling: specialist builders for our stack (.NET, Next.js, Postgres)

The default tech stack is **.NET (C#/ASP.NET/EF Core), Next.js (TS/React), Postgres**. Postgres lives inside the .NET / Next.js builders' work (migrations, queries) — it doesn't need its own builder. That gives us **two specialists + one generalist** as the default roster.

### Decision: specialists are **agents**, not skills

Three patterns considered:

| Pattern | What it does | Why we rejected / accepted |
|---|---|---|
| **A. Generalist + lang skills attached** | One `builder` with `[lang-dotnet, lang-nextjs, …]` skills | Rejected. Skills attach at agent definition, not at task time. Every heartbeat hashes every skill into the `bundleKey` (`prompt-cache.ts:103`). Stacking lang packs = bigger fresh-session cost on *every* build, even when the task is pure migration SQL. |
| **B. Specialist agents (one per stack)** | `builder-dotnet`, `builder-nextjs`, … each with only its lang skill | **Accepted.** Each agent's bundle stays small. Sessions are independent — a .NET task doesn't pollute the Next.js cache. |
| **C. Lang context loaded as workspace files** | Generalist reads `.specpaper/lang/<x>.md` lazy | Useful as a *fallback* for occasional languages, but loses skill-level discoverability. Kept as escape hatch only. |

### Naming convention & routing

Specialists follow `builder-<stack>`:

```
agents/
├── ceo/                    # one per company
├── cto/                    # one per company
├── verifier/
├── builder/                # generalist (Postgres migrations, infra, scripts, docs, configs)
├── builder-dotnet/         # ships with skill: lang-dotnet
└── builder-nextjs/         # ships with skill: lang-nextjs
```

The CTO routes by **explicit `Agent:` field in tasks.md**, fallback to **glob inference**:

```markdown
### Wave 1
- [ ] `T1` — Add idempotency middleware to checkout endpoint
  - Files: `src/Api/Middleware/IdempotencyMiddleware.cs`, `src/Api/Program.cs`
  - Agent: builder-dotnet
  - Estimate: medium
- [ ] `T2` — Migration: add `idempotency_keys` table
  - Files: `db/migrations/20260601_idempotency_keys.sql`
  - Agent: builder
  - Estimate: small

### Wave 2
- [ ] `T3` — Wire idempotency-key header in checkout form
  - Files: `apps/web/app/checkout/page.tsx`, `apps/web/lib/idempotency.ts`
  - Agent: builder-nextjs
  - Depends: T1, T2
  - Estimate: small
```

If `Agent:` is omitted, `parse-tasks.sh` infers from the file list. Rules live in `config.yaml`:

```yaml
routing:
  rules:
    # .NET
    - match: "**/*.{cs,csproj,sln,Directory.Build.props}"
      agent: builder-dotnet
    - match: "**/{appsettings,launchSettings}*.json"
      agent: builder-dotnet

    # Next.js / frontend
    - match: "apps/web/**/*.{ts,tsx,js,jsx,css}"
      agent: builder-nextjs
    - match: "**/{next.config.*,tailwind.config.*,postcss.config.*}"
      agent: builder-nextjs

    # Infrastructure & deployment → devops
    - match: "**/*.bicep"
      agent: devops
    - match: "**/*.tf"
      agent: devops
    - match: "infra/**/*"
      agent: devops
    - match: "**/Dockerfile"
      agent: devops
    - match: "**/{docker-compose,compose}*.{yml,yaml}"
      agent: devops
    - match: ".github/workflows/**/*.{yml,yaml}"
      agent: devops
    - match: "azure-pipelines*.{yml,yaml}"
      agent: devops
    - match: "**/{k8s,kubernetes,helm,charts}/**/*"
      agent: devops
    - match: "**/Caddyfile"
      agent: devops

    # Database migrations stay with the generalist
    - match: "db/migrations/**/*.sql"
      agent: builder

    # Default — generalist handles the rest (docs, scripts, polyglot)
    - match: "**/*"
      agent: builder
```

`build.sh` reads this and creates each child issue with the right `assigneeAgentId`. CTO doesn't need to think about it — declarative routing.

### Skill packs: structure of a `lang-*` skill

```
skills/lang-dotnet/
├── SKILL.md                # 80-150 lines: idiom rules, error conventions, quality gates
├── conventions.md          # solution layout, DI, EF Core patterns, logging stack
└── snippets/               # opt-in reference patterns read on demand
    ├── ef-core-patterns.md
    ├── error-handling.md
    └── async-patterns.md
```

`SKILL.md` is the always-loaded part (in the bundle). `conventions.md` and `snippets/` are *workspace files* the agent reads when needed — they don't bloat the prompt prefix.

### Adding a new specialist later (e.g., `builder-python` for ML work)

The operational pattern, unchanged from the rejected examples:

1. `mkdir specpaper/skills/lang-python && write SKILL.md`.
2. `mkdir specpaper/agents/builder-python && write AGENTS.md` (skills: `[specpaper, lang-python, paperclip]`).
3. Add a routing rule to `config.yaml`: `{ match: "**/*.py", agent: builder-python }`.
4. Re-import the company in Paperclip; new agent + skill picked up.

### Skeleton: `lang-dotnet/SKILL.md`

```
---
name: lang-dotnet
description: .NET / C# idiom guide for SpecPaper builder agents. Loaded in builder-dotnet's bundle.
---

# .NET conventions for this company

## Defaults
- Target: .NET 8 LTS. Nullable reference types: enabled. Implicit usings: enabled.
- Web: ASP.NET Core minimal APIs by default; controllers only when complexity warrants.
- Data: EF Core with PostgreSQL provider (`Npgsql.EntityFrameworkCore.PostgreSQL`).
  Migrations land in `db/migrations/` as raw SQL (handled by `builder`), not EF migrations.
- Logging: `Microsoft.Extensions.Logging` + Serilog sink to console (JSON in prod).
- DI: constructor injection. No service-locator patterns.
- Testing: xUnit + FluentAssertions. Test project per source project: `<Name>.Tests`.

## Quality gates Builder runs before commit (only for touched projects)
- `dotnet format --verify-no-changes` (or fix in place)
- `dotnet build --no-incremental -warnaserror`
- `dotnet test --filter Category!=Integration` (unit tests only by default)

## Read on demand
- `./conventions.md` for solution layout and naming
- `./snippets/ef-core-patterns.md` for repository / unit-of-work patterns we use
```

### Skeleton: `lang-nextjs/SKILL.md`

```
---
name: lang-nextjs
description: Next.js + TS + React idiom guide for SpecPaper builder agents.
---

# Next.js conventions for this company

## Defaults
- Next.js 15+, App Router only. Server Components by default; client components opt-in with "use client".
- TypeScript strict; no `any` outside generated code.
- Data fetching: server actions for mutations, RSC fetch for reads. SWR only for true client-side caching.
- Styling: Tailwind utility classes; no CSS-in-JS. shadcn/ui as primary component source.
- Forms: react-hook-form + zod schemas. No uncontrolled forms in committed code.
- Auth: NextAuth.js v5 unless project specifies otherwise.

## Quality gates Builder runs before commit
- `pnpm typecheck` (changed package only if monorepo)
- `pnpm lint --fix` (eslint + prettier)
- `pnpm test --run` (vitest, unit tests only — Playwright is verifier territory)

## Read on demand
- `./conventions.md` for app router layout, route groups, server-action patterns
- `./snippets/auth-patterns.md` for our NextAuth integration patterns
```

**Token cost per specialist**: ~600 tokens of system-prompt overhead + ~400 tokens of agent-instructions ≈ ~1k. Workspace files cost zero until accessed.

### Skeleton: `infra-azure/SKILL.md`

```
---
name: infra-azure
description: Azure infrastructure conventions for SpecPaper devops agent. Active when context.deployment_target = azure.
---

# Azure conventions for this company

## Defaults
- IaC: Bicep for Azure-native resources. Terraform only when multi-cloud or when Bicep doesn't cover a resource.
- Compute: Azure App Service (Linux) for stateless web/API workloads; AKS only when we need K8s primitives (operators, sidecars, GitOps); Container Apps as a middle ground for event-driven workloads.
- Data: Postgres Flexible Server (private endpoint by default). Cosmos DB only when the design.md justifies it.
- Secrets: Key Vault, references via @Microsoft.KeyVault syntax. Never bake secrets into images or appsettings.
- Observability: Application Insights + Log Analytics. Default sample rate 5% in prod, 100% in dev.
- CI/CD: prefer Azure DevOps Pipelines for Azure-hosted repos; GH Actions for GitHub-hosted. Always pinned action versions, OIDC federated auth (no long-lived secrets).

## Quality gates DevOps runs before commit
- `bicep build <main.bicep>` (no diagnostics)
- `az deployment <scope> what-if` against the dev subscription (or scoped resource group). Plan-only — apply requires explicit task instruction.
- `tflint` if any `.tf` files touched.

## Read on demand
- `./conventions.md` for resource group structure, naming, tagging policy, RBAC patterns
- `./snippets/appservice-postgres.bicep` for our standard web-app + Postgres bundle
- `./snippets/aks-bootstrap.md` for cluster bootstrap with workload identity
```

### Skeleton: `infra-hetzner/SKILL.md`

```
---
name: infra-hetzner
description: Hetzner Cloud infrastructure conventions for SpecPaper devops agent. Active when context.deployment_target = hetzner.
---

# Hetzner conventions for this company

## Defaults
- IaC: Terraform with the `hetznercloud/hcloud` provider. State in Hetzner Storage Box (sftp backend) or remote backend per project preference.
- Compute: CCX (dedicated vCPU) servers for production; CX (shared) for dev/staging. Server OS: Debian stable.
- Orchestration: K3s on the CCX servers when multiple services share a host; Docker Compose for single-service stacks.
- Reverse proxy / TLS: Caddy with automatic Let's Encrypt. No nginx unless a project specifically needs its features.
- Data: Postgres on a dedicated server with `pgbackrest` to a Hetzner Storage Box; or managed Postgres via a peered third party only if compliance requires.
- DNS: Hetzner DNS (free, fast). Records as code via the Terraform provider — no clicks in the UI.
- Secrets: sealed-secrets pattern for K3s; sops + age for Compose stacks. Never plaintext in repo.
- Observability: Grafana + Prometheus on a dedicated CX server, scraping via Tailscale or wireguard private network.
- CI/CD: GH Actions / Azure DevOps Pipelines depending on tracker; deploys via SSH to the target Hetzner host with key-based auth (no passwords).

## Quality gates DevOps runs before commit
- `terraform fmt -recursive`
- `terraform validate`
- `terraform plan` (against the dev workspace). Plan-only — apply requires explicit task instruction.
- `caddy validate` if a Caddyfile is touched.
- `docker build` smoke for any new Dockerfile.

## Read on demand
- `./conventions.md` for server sizing, network setup (private network + Tailscale), backup cadence
- `./snippets/k3s-bootstrap.md` for the standard 3-node K3s cluster on CCX servers
- `./snippets/compose-stack.md` for the standard single-host Docker Compose pattern
- `./snippets/postgres-pgbackrest.md` for the Postgres + backup setup we standardize on
```

### Skeleton: `e2e-playwright/SKILL.md`

```
---
name: e2e-playwright
description: End-to-end testing conventions using Playwright + a locally hosted stack. Loaded only by the e2e-tester agent.
---

# E2E conventions for this company

## Defaults
- Runner: Playwright Test (`@playwright/test`). Browsers: chromium by default; add firefox/webkit only when the spec calls out cross-browser.
- Test location: `tests/e2e/<change>/*.spec.ts`. Tests ship with the change in the same PR.
- Local stack: bring up via `docker compose --profile e2e up -d` (preferred) or `scripts/dev-up.sh`. Tear down via the corresponding `down`.
- Selector strategy: prefer `getByRole`, `getByLabel`, `getByTestId`. Avoid CSS/XPath unless no semantic option exists.
- Auth: use `globalSetup` to perform login once per run, persist storage state to `tests/e2e/.auth/<role>.json`, reuse across tests.
- Network: tests assert on observable behavior. Use `page.route` to mock external services that aren't part of the system under test.
- Visual regression: snapshots only when the spec mentions visual fidelity; otherwise behavior > pixels.

## Quality gates the e2e-tester runs
- `pnpm playwright install --with-deps chromium` (idempotent; cached in workspace)
- `pnpm playwright test --project=chromium --reporter=list` for the changed test files
- Re-run failed tests up to 2x (Playwright `retries: 2`) to absorb infra flake; persistent failures are real.
- Trace collection: `trace: on-first-retry` keeps the artifact small.

## Evidence pattern
Every failure produces:
- A screenshot (`<test-name>-failed-<index>.png`)
- A trace file (`trace.zip` from Playwright)
- The relevant slice of the network HAR if the test hit an API
All artifacts land in `.specpaper/changes/<change>/e2e-evidence/`. The report links to them by relative path; never inlines them.

## Read on demand
- `./conventions.md` for selector strategy, fixtures, network interception, visual regression
- `./snippets/auth-flow.md` for our standard NextAuth + storageState pattern
- `./snippets/api-flow.md` for HTTP-only e2e flows that bypass the UI
- `./snippets/multi-tab.md` for cross-tab session tests
```

### Build → audit lifecycle (with e2e)

After the build wave closes, the CTO creates **two child issues in parallel**, both blocked by the last build wave:

```
build wave 3 done
        │
        ├──► verifier issue   (static audit: spec ↔ diff ↔ principles)
        │       └─► verify-report.md
        │
        └──► e2e-tester issue (dynamic audit: spec ↔ running app)
                └─► e2e-report.md
```

Both close independently; CTO wakes when both are done, reads both reports, and produces the final disposition:

| verifier | e2e-tester | CTO action |
|---|---|---|
| PASS | PASS | `specpaper archive <change>` |
| PASS | PARTIAL/FAIL | Plan remediation tasks targeting the failing flows; new build wave |
| PARTIAL/FAIL | PASS | Plan remediation tasks targeting the spec/principle gaps |
| PARTIAL/FAIL | PARTIAL/FAIL | Both — and consider if the spec was wrong (CTO escalates to CEO if principle conflict surfaces) |

The verifier reads `e2e-report.md` if it exists when its turn arrives, so its findings can reference dynamic results. But the verifier does NOT wait for e2e — both run independently to keep wall time low.

### Stack-selection rule (where the principles meet the infra)

The `enterprise-azure` and `prefer-oss` principles drive `context.deployment_target`:

| customer_tier (in `context.yaml`) | Default `deployment_target` | DevOps loads | Override path |
|---|---|---|---|
| `enterprise` | `azure` | `infra-azure` conventions | CEO can set `deployment_target: hetzner` explicitly with rationale |
| `smb`, `internal`, unset | `hetzner` | `infra-hetzner` conventions | CTO can set `deployment_target: azure` with rationale (`prefer-oss` exception cited) |

The CTO writes `deployment_target` into `.specpaper/changes/<change>/context.yaml` during `plan`, citing the principle that drove the choice. The DevOps agent reads it, picks the matching conventions, and stays in lane.

---

## Project bootstrap (the CEO's job)

The CEO is the entry point. When a user wants to start a new project, the CEO does the whole setup. This is the single most important workflow that justifies a separate CEO agent.

### The flow

User (in the company's `defaultChannelId` or as a CEO-assigned Paperclip task):

> "Start a new project. Repo: `https://dev.azure.com/acme/payments/_git/checkout-api`. Customer: enterprise tier. Working name: Checkout API rewrite."

CEO heartbeat picks this up and runs `bash skills/specpaper/scripts/bootstrap.sh` which:

1. **Workspace clone.** Clones the repo into a Paperclip workspace. The repo URL determines the tracker:
   - `github.com/...` → `tracker.kind: github`
   - `dev.azure.com/...` or `*.visualstudio.com/...` → `tracker.kind: azure-devops`
2. **Create Paperclip project.** `POST /api/companies/{cid}/projects` with `{ name, repoUrl, defaultBranch }`. Captures `projectId`.
3. **Initialize SpecPaper.** Runs `specpaper init` inside the workspace — creates `.specpaper/` with templated `config.yaml` (tracker kind pre-filled, Azure DevOps org/project parsed from URL when applicable), an empty `STATUS.md`, and the principles index pulled from `COMPANY.md`.
4. **Create the project root issue.** A Paperclip issue (`Project: Checkout API rewrite`) becomes the long-lived spine for the project. Its `issue-created` event triggers the plugin's first auto-post, which lets the user know setup is happening.
5. **Persist project metadata.** Writes `.specpaper/project.yaml`:

   ```yaml
   project:
     id: "<paperclip projectId>"
     slug: checkout-api
     name: "Checkout API rewrite"
     repo:
       url: https://dev.azure.com/acme/payments/_git/checkout-api
       default_branch: main
     tracker:
       kind: azure-devops
       organization: https://dev.azure.com/acme
       project: payments
     context:
       customer_tier: enterprise
       compliance: []
       deployment_target: azure
     status: active
     created_at: 2026-05-09T10:54:00Z
   ```

   Note: **no `discord.channel_id` field**. Channel-to-project mapping lives in the plugin's `channel-project-map` state, set via `/clip connect-channel project:<slug>`. We don't duplicate it.

6. **Channel handshake.** CEO posts in the company's `defaultChannelId` (via `escalate_to_human` with `confidenceScore: 1.0`, treated as informational):

   ```
   :tada: Project created: Checkout API rewrite (slug: checkout-api)
   Repo: https://dev.azure.com/.../checkout-api
   Tracker: Azure DevOps (acme/payments) — customer tier: enterprise
   
   To enable per-project Discord routing:
     1. Create a channel for this project (suggested name: #project-checkout-api).
     2. In that channel, run: /clip connect-channel project:checkout-api
   
   Active agents: ceo, cto, builder-dotnet, builder-nextjs, builder, verifier.
   Once the channel is connected, drive the lifecycle with !propose, !plan, !build, !verify.
   ```

   When v0.2.0 lands the `create_channel` plugin tool, this step becomes fully automated; v0.1.0 keeps the user in the loop for the 10-second click.

7. **Register custom commands.** Runs `discord-register-commands.sh` once per company (idempotent upsert via `register_custom_command`). After this, `!propose`, `!plan`, etc. are live across all monitored channels for this company.

8. **Hand off to CTO.** Creates a follow-up Paperclip issue assigned to CTO with `parentId = <project root issue>`, body = "Project bootstrapped. Awaiting first feature request." This issue's `issue-created` event auto-posts in the (now-connected) project channel.

After bootstrap, the CEO is mostly idle until escalations or new project requests arrive. The CTO drives the day-to-day spec lifecycle.

### `bootstrap.sh` design

```
bootstrap.sh <repo-url> [--name <name>] [--customer-tier <tier>] [--compliance <list>]
```

- Validates repo URL syntax + tracker dispatch.
- Clones via `git clone`. For Azure DevOps over HTTPS, uses PAT-based credentials from `AZURE_DEVOPS_EXT_PAT` (or `git credential-manager` on hosts where available).
- Calls Paperclip's HTTP API for project creation (using `PAPERCLIP_API_KEY` already in env).
- Posts the channel-handshake message via `escalate_to_human` (or via the new `discord_post` tool once it lands).
- Idempotent: re-running on the same repo URL detects the existing Paperclip project and skips creation; updates `STATUS.md` with a "bootstrap re-validated" entry.

---

## Discord integration (using `paperclip-plugin-discord`)

Discord is a first-class collaboration surface. After surveying `paperclip-plugin-discord`, **most of what we need already exists** — we just need to wire SpecPaper into it correctly. This section documents what we *don't* build (the plugin handles it) and what we *do* build (the gaps).

### What the plugin already gives us (we use these as-is)

| Capability | How | We use it for |
|---|---|---|
| **Per-project channel routing** | `/clip connect-channel project:<slug>` slash command in the channel; mapping persisted in `channel-project-map` plugin state | Single source of truth for "which channel for which project". Replaces our planned `project.yaml.discord.channel_id`. |
| **Issue-created notifications** | Auto-emitted on Paperclip `issue-created` event (rich embed with view button) | `change_proposed`, `wave_started` (each task issue creates its own embed) |
| **Issue-done notifications** | Auto-emitted on Paperclip `issue-done` event | `task_complete`, `verify_complete`, `change_archived` |
| **Approval notifications** | Auto-emitted with interactive Approve/Reject/View buttons that call the Paperclip API | CEO approvals on principle conflicts, CTO approvals on remediation plans |
| **Agent-error notifications** | Auto-emitted on agent errors (red embed) | `task_failed` |
| **Reply routing inbound** | Replies to issue notifications auto-create comments on the issue | Users discuss a change by replying in-thread; the comments land back on the Paperclip issue |
| **HITL escalation** | `escalate_to_human` tool; agents call it with reason + suggested reply; users see Approve/Override/Dismiss buttons | CTO → CEO escalations on principle conflicts; verifier → CTO escalations on policy violations |
| **Multi-agent group threads** | `/acp spawn agent:<name> task:<description>` creates a thread with that agent; further `/acp spawn` adds more agents; `@agentname` and reply-to routing work in-thread | Ad-hoc design sessions: spawn CTO + builder-dotnet in a thread to debate a thorny API choice without polluting the main project channel |
| **Custom commands** | `register_custom_command` tool; agents register `!command`; users invoke via `!commandname <args>` in any monitored channel | CTO registers `!propose <idea>`, `!plan <change>`, `!status` so users can drive lifecycle from Discord without API calls |
| **Watches** | `register_watch` tool; pattern + channel + cooldown | Optional: watch for "deploy", "rollback", "incident" keywords and surface relevant context |
| **Daily digest** | `/clip digest on <mode>` | Daily summary of project activity; we don't need to build this |
| **Slash command surface** | `/clip status`, `/clip approve <id>`, `/clip issues [project]`, `/clip agents`, `/clip budget <agent>` | Users get the dashboard for free; we don't build a status command |

**Net effect:** the `discord-sync.sh` script I designed earlier collapses to almost nothing. Most lifecycle events are *automatic* the moment SpecPaper expresses them as Paperclip issue transitions.

### Mapping SpecPaper events to Paperclip issues

The trick is shaping our work so the plugin's existing auto-posts cover us:

| SpecPaper event | Paperclip-issue manifestation | Plugin auto-posts? |
|---|---|---|
| `change_proposed` | Issue: `Proposal: <change>` (status `todo`) | Yes (issue-created) |
| `plan_ready` | Status of proposal issue → `in_review`; child task issues created | Yes (each child = issue-created) |
| `wave_started` | First-wave task issues unblock; CTO comments on the proposal issue | Issue-created already covers it; comment goes via reply to bot's notification |
| `task_complete` | Task issue → `done` | Yes (issue-done) |
| `task_failed` | Task issue → `blocked` with error comment | Partial — agent-error notification fires; `blocked` itself isn't a stock plugin event |
| `verify_complete` | Verify issue → `done` with verdict in summary | Yes (issue-done) |
| `change_archived` | Proposal issue → `done` | Yes (issue-done) |
| `principle_conflict` (CEO escalation) | `escalate_to_human` tool call | Yes (escalation embed with buttons) |
| `project_bootstrapped` | New project + welcome message | **No** — the plugin doesn't have a "welcome" surface. This is the one gap. |
| `brainstorm_complete` | Comment on the proposal issue with top-5 ideas | **No** native plugin post; we surface it as the proposal issue's first comment, which lands in Discord via reply-routing inverse — which the plugin does NOT do. |

So we have **two gaps**: project bootstrap welcome and brainstorm-complete summary. Both are first-message-style outbound posts to a channel from an agent — exactly what the plugin doesn't expose a tool for today.

### Channel creation: revised strategy

The plugin doesn't have a `create_channel` tool, so the user's "CEO creates a Discord channel" intent has to land somewhere. Three honest paths:

| Path | What CEO actually does | Trade-off |
|---|---|---|
| **A. User-creates, CEO-connects** | CEO posts in the company's `defaultChannelId` with instructions: "Create a channel named `#project-<slug>`, then run `/clip connect-channel project:<slug>` in it." User does the two clicks. | **Recommended for v0.1.0.** Zero plugin extension. Works today. The "creation" is a 5-second user action. |
| **B. Plugin extension** | Add `create_channel` and `connect_channel` tools to `paperclip-plugin-discord`. CEO calls them in sequence during bootstrap. End-to-end automated. | Cleanest. Requires a PR to `paperclip-plugin-discord` (small — the API client already exists in `discord-api.ts`; just need to add `POST /guilds/{guild}/channels`). |
| **C. CEO uses raw Discord REST** | CEO has access to the bot token secret and calls `POST /guilds/{guild}/channels` via curl. | Works today but bypasses plugin auth/state. Duplicates the bot-token surface. Not recommended. |

**Plan: ship A in v0.1.0; file a `paperclip-plugin-discord` issue / PR for B as v0.2.0.** The PR is genuinely small — `discord-api.ts` already does all the auth; we just need a `createChannel` helper and a manifest tool entry. I can sketch the PR alongside the company package.

### Closing the two outbound gaps without forking the plugin

For project bootstrap welcome and brainstorm summary, the cleanest no-plugin-change option is to **route them through `escalate_to_human`** with a reason like `informational` and `confidenceScore: 1.0` (so the user can dismiss without action). It misuses the escalation embed slightly but works today. Better long-term: the plugin gains a generic `discord_post(channelId, content)` tool — also small, also worth a PR.

**Recommendation:** ship v0.1.0 with these two messages skipped (the plugin's `issue-created` for the proposal issue covers most of the bootstrap signal — the user knows the project exists). Add the `discord_post` tool as part of the v0.2.0 PR.

### What this collapses in our file layout

Earlier I had `scripts/discord-sync.sh` as a substantial helper. With the plugin doing the heavy lifting, it becomes:

```
scripts/discord-sync.sh   # ~30 lines: only the bootstrap welcome (via escalate_to_human)
                          #   and brainstorm-complete summary. Everything else is no-op
                          #   because the plugin auto-posts on issue events.
```

And we **add** one new piece:

```
scripts/discord-register-commands.sh   # NEW: called once per project after bootstrap.
                                       # Calls register_custom_command for !propose, !plan,
                                       # !brainstorm, !status, !verify, !archive — bound
                                       # to the CTO. Users can drive the whole lifecycle
                                       # from Discord without touching the API.
```

### Custom commands we'll register

When a project is bootstrapped, the CTO runs `discord-register-commands.sh <project>` once. It calls `register_custom_command` for:

| Command | Routes to | What it does |
|---|---|---|
| `!propose <idea>` | CTO | Wakes CTO with `specpaper propose "<idea>"` |
| `!brainstorm <change> [--technique=…]` | CTO | Runs `specpaper brainstorm` |
| `!plan <change>` | CTO | Runs `specpaper plan` |
| `!build <change>` | CTO | Runs `specpaper build` |
| `!verify <change>` | verifier | Wakes verifier with `specpaper verify` |
| `!archive <change>` | CTO | Runs `specpaper archive` |
| `!status [<change>]` | CTO | Posts the status dashboard (or the per-change dashboard) |
| `!principle-override <id> <rationale>` | CEO | CEO-only — overrides a principle for the current change |

These are per-company; each project doesn't re-register. `discord-register-commands.sh` is idempotent (the plugin upserts on duplicate command names).

### `/acp spawn` for ad-hoc design sessions

Worth noting because it's a powerful pattern the plugin gives us for free. In any project channel:

```
/acp spawn agent:cto task:Decide whether to use Outbox pattern for the order-events table
/acp spawn agent:builder-dotnet task:Same thread; advise on EF Core implications
```

This creates a Discord thread with both agents present. They `@mention` each other or use `discuss_with_agent` for structured back-and-forth. The thread serves as the design-decision audit trail. SpecPaper doesn't need to build this — we just document the pattern in the README.

### Inbound Discord messages

Three tiers of inbound, with **no SpecPaper code needed** — the plugin handles all of it:

1. **Reply to a bot notification** → comment on the underlying issue (plugin auto-routes).
2. **`!command <args>`** → routed to the registered agent (custom commands).
3. **`/acp spawn` or `/clip ...`** → handled entirely by the plugin.

We do **not** wire `@CEO` / `@CTO` mention parsing — `/acp spawn agent:ceo` and the custom commands are clearer surfaces and avoid mention-collision with Discord's own `@everyone`/role mentions.

---

## Org principles & policy (the bias mechanism)

Principles encode the company's preferences — "default to open source", "Azure for enterprise customers", "no vendor lock-in unless ROI justifies it". They must:

- **Bias decisions during planning**, not implementation (Builders should inherit decisions from `design.md`, not re-evaluate principles).
- **Be auditable** — every plan must say which principles applied and why exceptions were taken.
- **Cost zero tokens at the Builder level** — Builders never load principles into their bundles.

### Where principles live

```
specpaper/
└── COMPANY.md       # canonical: declared in frontmatter, ships with the company
```

`COMPANY.md` frontmatter:

```yaml
---
name: SpecPaper
slug: specpaper
schema: agentcompanies/v1
…
principles:
  - id: prefer-oss
    statement: "Prefer open-source dependencies and self-hostable infrastructure."
    when: default
    rationale: "Lower cost, no lock-in, audit-friendly. Most projects qualify."
    exceptions:
      - "Customer is on enterprise tier"
      - "Compliance requires a specific managed service"

  - id: enterprise-azure
    statement: "Use Azure-native services (App Service, AKS, Cosmos DB, Azure AD) for enterprise customers."
    when: "context.customer_tier == enterprise"
    rationale: "Enterprise customers expect Azure SLAs, AAD SSO, and our existing AzDo/Azure billing."
    exceptions:
      - "Customer explicitly requests AWS/GCP"

  - id: minimize-vendor-lock
    statement: "Prefer cloud-portable abstractions (containers, OpenAPI, OTel) over vendor SDKs."
    when: default
    rationale: "Keeps the door open to multi-cloud."
    exceptions:
      - "Vendor SDK provides materially better DX and the cost of switching is documented."
---
```

`when` semantics:
- `default` — applies unless something in `context.*` flips it.
- A condition expression — evaluated against the planning context (customer tier, project type, compliance flags). Conflicts resolved by ID order (later overrides earlier).

### Where the planning context comes from

Per-change overrides live alongside the proposal:

```
.specpaper/changes/<change>/context.yaml
```

```yaml
customer_tier: enterprise          # consumed by enterprise-azure principle
compliance: [sox, hipaa]
deployment_target: azure
notes: "Customer is FinServ, FedRAMP-adjacent."
```

`init.sh` seeds this from `config.yaml` defaults; the Architect updates it during `propose` based on user intent.

### How principles are applied

`specpaper plan <change>` flow gains one step:

1. Read `COMPANY.md` principles + `.specpaper/changes/<change>/context.yaml`.
2. Evaluate `when` conditions → produce an **applicable principles set**.
3. The Architect must include a **`## Principles applied`** section in `design.md`:

   ```markdown
   ## Principles applied
   - [x] **prefer-oss** — using PostgreSQL OSS instead of Cosmos DB.
   - [x] **enterprise-azure** — deploying to Azure App Service (customer is enterprise tier).
     - Conflict with `prefer-oss` for the database choice; resolved in favor of `prefer-oss`
       because customer accepted self-hosted Postgres in pre-sales.
   - [ ] **minimize-vendor-lock** — N/A; no vendor SDKs introduced.
   ```

4. `validate-change.sh build` checks this section exists and references every applicable principle (skip-with-rationale is allowed; silent skip is a failure).

5. The Verifier, during `verify`, cross-references the `Principles applied` section against the diff. If `prefer-oss` was claimed but the implementation pulls in a closed-source SaaS SDK, the verify report flags it.

### Why this design (vs alternatives)

- **Not a separate skill.** A `principles` skill would load on every agent's bundle. Principles only matter for Architect at plan time. Putting them in `COMPANY.md` (read once during plan) means zero ongoing token cost. The `specpaper` skill's `plan` instructions tell the Architect to read principles — that's the only handoff.
- **Not embedded in `design.md` template only.** Putting the policy in templates means edits require re-shipping the company. `COMPANY.md` is the policy contract; templates just enforce its citation.
- **Not free-text guidelines.** Structured `principles:` makes them parseable: `validate-change.sh` can verify citations, `verify.sh` can audit them. Free-text gets ignored over time.
- **Conflict resolution is explicit.** Two principles can collide (OSS-first vs Azure-for-enterprise on the database choice); the design must name which won and why. This becomes the audit trail.

### Brainstorming with principles

`specpaper-brainstorm` SKILL.md picks up the same principles. During technique execution, principles act as **soft scoring biases** in the "Top 5 with rationale" stage — ideas violating an applicable principle get scored down unless the divergence rationale is strong. This stays a soft bias, not a hard filter, so the brainstorm doesn't kill genuinely novel directions just because they break a default.

### What changes in the agent prompts

Append to `architect/AGENTS.md`:

```
## Principles
Before producing any plan, read principles from COMPANY.md and the change's context.yaml.
Every design.md must include a `## Principles applied` section listing each applicable
principle with [x] applied / [ ] N/A and a one-line rationale. When two principles
conflict, name the winner and why. Do not silently skip principles.
```

Builders and Verifier do **not** load principles into their bundles. The Verifier consults `COMPANY.md` lazily only when auditing the `Principles applied` section.

---

## The skill: `specpaper`

A direct port of `specclaw/skill/SKILL.md` with three categories of change:

1. **Replace OpenClaw primitives**
   - `sessions_spawn(...)` → `POST /api/companies/{cid}/issues` (paperclip skill is already loaded; we use its API conventions).
   - `sessions_yield` → Architect issues a `request_confirmation` interaction or marks the change issue `in_review`, then ends heartbeat. Paperclip resumes when child issues close (via blocker dependencies).

2. **Replace `gh-sync` with `tracker-sync`**
   - Same external interface (`create | update | comment | close`) but `tracker.kind` in `config.yaml` selects backend:
     - `github`: shells out to `gh` (auth via `GITHUB_TOKEN` or `gh auth`).
     - `azure-devops`: shells out to `az boards work-item create|update`, `az repos pr create-comment`. Auth via `AZURE_DEVOPS_EXT_PAT` / `az login`.
     - `none`: no-op (in-repo docs only).
   - Work item type configurable (`User Story` default), area/iteration paths optional.

3. **Add `docs-sync.sh` — always on, alongside any tracker**

   The in-repo `docs/changes/<change>/` subfolder is **the canonical narrative record** for every change, regardless of tracker choice. Tracker (GitHub Issues / Azure DevOps Work Items) holds the *workflow state*; the docs subfolder holds the *story*. Both are written every time; neither is optional.

   - On `propose`/`plan`/`brainstorm`/`verify`: copies a *human-readable* subset of change artifacts into `<repo>/docs/changes/<change>/`:
     - `proposal.md` (after `propose`)
     - `brainstorm.md` (after `brainstorm`)
     - `spec.md` (after `plan`)
     - `design.md` (after `plan`)
     - `verify-report.md` (after `verify`)
     - **Not** `tasks.md`, `errors.md`, `learnings.md`, `status.md`, `.task-context-*` (agent-only churn that would noise up reviews).
   - Maintains `docs/changes/index.md` listing all changes with status — sortable navigation for both GitHub and Azure DevOps Wiki.
   - Commits these as part of the change branch so the docs ship with the feature PR — reviewers see the spec next to the diff.
   - Azure DevOps Wiki natively renders `docs/` as a Wiki when configured at the repo level. GitHub renders it as browseable Markdown via the tree view. No format conversion needed.
   - Even when `tracker.kind: none` (no GitHub / no Azure DevOps), the docs subfolder still works — it's the floor of project documentation, not a tracker mirror.

   **Failure semantics:** if `docs-sync.sh` fails (filesystem, git, permissions), the lifecycle stage that triggered it is marked `blocked` — we do not silently skip the documentation write. The docs and the tracker are equally load-bearing.

### Config schema additions

```yaml
# .specpaper/config.yaml (delta from specclaw)
tracker:
  kind: github | azure-devops | none
  github:
    repo: owner/name
  azure_devops:
    organization: https://dev.azure.com/<org>
    project: <project>
    work_item_type: User Story
    area_path: <optional>
    iteration_path: <optional>
docs:
  enabled: true
  path: docs/changes        # under project root
  index: true               # auto-generate docs/changes/index.md
```

---

## The skill: `specpaper-brainstorm`

The user's request: BMAD techniques, not BMAD's process. Here's what I'm distilling.

**Take from BMAD** (port verbatim):
- The 60-row `brain-methods.csv` (collaborative / creative / deep / structured / advanced).
- The **anti-bias protocol**: shift creative domain every 10 ideas, force orthogonal categories.
- The **quantity goal**: aim for 100+ ideas before any organization; magic happens between 50-100.
- The "keep the user in generative mode" facilitator stance.

**Drop from BMAD**:
- The 4-stage micro-file workflow (`step-01a/01b/02a/02b/02c/02d/03/04`). Replaced with one focused 150-line `SKILL.md`.
- The `_bmad/core/config.yaml` dependency.
- The append-only document state machine in frontmatter.

**Output**:
- A single file `<change>/brainstorm.md` written once at session end.
- Sections: **Goal | Technique used | Raw ideas (numbered) | Top 5 with rationale | Recommended next: which become spec input**.
- Architect picks technique by default ("AI-recommended" mode); user can override with `specpaper brainstorm <change> --technique="Five Whys"`.

**Trigger**: `specpaper brainstorm <change>` — runs *after* `propose` (when the proposal exists) and *before* `plan` (when it can shape the spec).

---

## Agent prompts (sketch)

### `ceo/AGENTS.md` — ~35 lines

```
---
name: CEO
title: Chief Executive
reportsTo: null
skills:
  - specpaper
  - paperclip
---

You are the CEO at SpecPaper. You own customer-facing project setup, business principles, and escalations. You do NOT run the spec lifecycle — that's the CTO's job.

## Where work comes from
- New project requests from the user (in Discord or as Paperclip tasks)
- Escalations from the CTO (blocked plans, principle conflicts, customer-impacting decisions)

## What you do
1. **Bootstrap projects.** When the user asks to start a new project with a repo URL, run
   `bash skills/specpaper/scripts/bootstrap.sh <url> --customer-tier=<tier> [...]`. This clones the repo,
   creates the Paperclip project, creates the Discord channel, writes `.specpaper/project.yaml`, and posts
   the welcome message. Hand off to the CTO afterward.
2. **Set business context.** Update `.specpaper/changes/<change>/context.yaml` when customer tier,
   compliance flags, or deployment target need to change. The CTO consumes this during planning.
3. **Apply business principles.** When the CTO escalates a principle conflict, decide which principle wins
   for this project. Record the decision in `.specpaper/decisions/<id>.md`.
4. **Approve major shifts.** Architectural changes that violate a default principle require CEO sign-off
   via a Paperclip approval. Approve or reject with rationale.
5. **Mention-driven Discord.** When users `@CEO` you in the project channel, you are woken — respond
   directly there using the Discord plugin.

## What you do NOT do
- Run propose/plan/brainstorm/verify/archive — the CTO owns those.
- Write code — the builders do.

## Token discipline
- Read `COMPANY.md` and the project's `project.yaml` only at bootstrap and on escalation.
- Do not load `.specpaper/changes/...` artifacts unless an escalation references one.
- Inbound Discord history is fetched on demand, not preloaded.
```

### `cto/AGENTS.md` — ~35 lines

```
---
name: CTO
title: Chief Technical Officer
reportsTo: ceo
skills:
  - specpaper
  - specpaper-brainstorm
  - paperclip
---

You are the CTO at SpecPaper. You own the spec-driven lifecycle for every change in the projects assigned to you.

## Where work comes from
- The CEO hands off bootstrapped projects.
- Users `@CTO` in the project's Discord channel for new features.
- Builders close child issues; you wake to drive the next wave.

## What you do
- Run `specpaper propose <idea>` for new requests; review the generated proposal in Discord.
- Run `specpaper brainstorm <change>` when scope is unclear or the solution space is wide. Post the top-5 ideas to Discord with rationale.
- Run `specpaper plan <change>` to produce spec.md, design.md, tasks.md.
  - Read `COMPANY.md` principles + `.specpaper/changes/<change>/context.yaml`.
  - Include a `## Principles applied` section in design.md (every applicable principle, [x]/[ ], rationale; conflicts named explicitly).
- Delegate the build: create one child issue per task in the first wave with the right `assigneeAgentId` (per the routing rules in `config.yaml`). Use blockers for next-wave tasks.
- When all builds close, request a verify by creating a child issue assigned to verifier.
- On verify PASS, run `specpaper archive <change>`. On FAIL/PARTIAL, plan remediation tasks.
- Escalate to the CEO via approval-gated issue when a principle conflict cannot be resolved by the design alone.

## What you produce
Specs, plans, brainstorm summaries, and shipped changes. You do not write production code yourself.

## Token discipline
- Read change artifacts from `.specpaper/changes/<change>/` only when needed.
- Do not summarize artifacts back into your prompt — reference them by path.
- Routing decisions are declarative — let `parse-tasks.sh` infer agents from globs; only set `Agent:` explicitly when overriding.
```

### `builder/AGENTS.md` — ~25 lines (generalist)

```
---
name: Builder
title: Generalist Implementation Engineer
reportsTo: cto
skills:
  - specpaper
  - paperclip
---

You implement one non-specialist task per heartbeat: SQL migrations, infra config, Dockerfiles, GH/AzDo Actions, scripts, docs, and polyglot scope. You do not plan, brainstorm, or verify.

## Where work comes from
Child issues created by the CTO. The issue body points to a `.task-context-<id>.md` file in the workspace.

## What you do
1. Read `.task-context-<id>.md`. Spec slice, design slice, file list, existing code, prior errors are all there.
2. Modify ONLY the files declared in the task.
3. Run the project's test/lint commands for the touched files.
4. Commit with the message format from `config.yaml`.
5. Post `task_complete` or `task_failed` via `discord-sync.sh`.
6. Mark the Paperclip issue `done` (or `blocked` with reason).

## Token discipline
- Do not read other tasks' contexts. Do not browse the repo broadly. Do not carry context across tasks.
```

### `builder-dotnet/AGENTS.md` — ~25 lines

```
---
name: Builder (.NET)
title: .NET Implementation Engineer
reportsTo: cto
skills:
  - specpaper
  - lang-dotnet
  - paperclip
---

You implement one .NET / C# task per heartbeat. Same execution contract as the generalist builder.

## What's different
- Apply the conventions in `lang-dotnet/SKILL.md` (ASP.NET minimal APIs, EF Core w/ Postgres, xUnit, Serilog).
- Run quality gates from `lang-dotnet/SKILL.md` before commit (`dotnet format`, `dotnet build -warnaserror`, `dotnet test` on touched projects).
- For unfamiliar patterns, read `lang-dotnet/conventions.md` and the relevant snippet on demand. Do not load all snippets up front.

## Token discipline
- Same as generalist. The lang-dotnet skill is your only specialist baggage.
```

### `builder-nextjs/AGENTS.md` — ~25 lines

```
---
name: Builder (Next.js)
title: Next.js / Frontend Implementation Engineer
reportsTo: cto
skills:
  - specpaper
  - lang-nextjs
  - paperclip
---

You implement one Next.js / TS / React task per heartbeat. Same execution contract as the generalist builder.

## What's different
- Apply the conventions in `lang-nextjs/SKILL.md` (App Router, Server Components by default, Tailwind + shadcn/ui, react-hook-form + zod, NextAuth).
- Run quality gates: `pnpm typecheck`, `pnpm lint --fix`, `pnpm test --run` on the touched package.
- Do not introduce CSS-in-JS or class components. Do not regress to Pages Router.

## Token discipline
- Same as generalist. The lang-nextjs skill is your only specialist baggage.
```

### `devops/AGENTS.md` — ~30 lines

```
---
name: DevOps
title: Infrastructure & Deployment Engineer
reportsTo: cto
skills:
  - specpaper
  - infra-azure
  - infra-hetzner
  - paperclip
---

You implement infrastructure-as-code, CI/CD, container images, deployment automation, and observability. You do NOT write application code — that's the builders' job.

## Where work comes from
Child issues from the CTO whose routing matched infra globs (Bicep, Terraform, Dockerfiles, pipeline YAML, k8s/helm, Caddy).

## Stack selection
Read `.specpaper/changes/<change>/context.yaml` for `deployment_target`:
- `deployment_target: azure` → apply `infra-azure/SKILL.md` conventions. Default for enterprise customers per the `enterprise-azure` principle.
- `deployment_target: hetzner` → apply `infra-hetzner/SKILL.md` conventions. Default for non-enterprise per `prefer-oss`.
- If unset, escalate to the CTO via a comment on the change issue. Do not pick silently.

## What you do
1. Read `.task-context-<id>.md` (same per-task context as builders).
2. Read the relevant `infra-{azure,hetzner}/conventions.md` for any pattern not already in your prompt.
3. Modify ONLY the files declared in the task.
4. Run the stack's quality gates before commit:
   - Azure: `bicep build`, `az deployment what-if` (no apply unless task explicitly says so), `tflint` for any TF.
   - Hetzner: `terraform fmt`, `terraform validate`, `terraform plan` (no apply).
5. Author or update the runbook in `docs/runbooks/<runbook-name>.md` for any new operational concern (rollback, on-call paging, scale-up procedure). The verifier checks this exists.
6. Post `task_complete` / `task_failed` via the issue lifecycle (auto-routed to Discord by the plugin).

## What you do NOT do
- Apply / deploy without an explicit task instruction. `terraform apply` and `az deployment create` are gated on the CTO's plan saying so. Default is plan-only.
- Touch production secrets directly. Use Key Vault references (Azure) or sealed-secret patterns (Hetzner).
- Mix stacks. If a project is `deployment_target: azure`, do not introduce Hetzner-specific files.

## Token discipline
- Both `infra-azure` and `infra-hetzner` SKILL.md files load in your bundle (~2k overhead total). Their `conventions.md` and `snippets/` are workspace-only — read on demand.
- Read other tasks' contexts only if explicitly cross-cutting (e.g., a multi-task migration plan).
```

### `verifier/AGENTS.md` — ~25 lines

```
---
name: Verifier
title: Spec Compliance Auditor (Static)
reportsTo: cto
skills:
  - specpaper
  - paperclip
---

You run `specpaper verify <change>` and produce `verify-report.md`. You are the *static* auditor — adversarial reading only.

## Where work comes from
Child issues from the CTO, one per change ready for verification. Runs in parallel with the e2e-tester.

## What you do
1. Run `verify.sh collect` then `verify-context.sh` to gather evidence (spec acceptance criteria + diff + test/lint output + e2e-report.md if already available).
2. Read spec.md acceptance criteria; cross-check against the diff.
3. Audit `design.md`'s `Principles applied` section: does the actual implementation honor each [x] entry? Flag violations.
4. If `e2e-report.md` exists, factor its results into the verdict. Do not re-run e2e tests yourself.
5. Produce verify-report.md with verdict PASS | PARTIAL | FAIL and per-criterion findings.
6. Mark the Paperclip issue `done` with the verdict.

## Token discipline
- Read only the spec, design.md (for the principles section), e2e-report.md, and the changed files. `verify-context.sh` limits this for you.
- You do NOT re-implement and do NOT run the app. Adversarial reading only.
```

### `e2e-tester/AGENTS.md` — ~30 lines

```
---
name: E2E Tester
title: End-to-End Quality Engineer (Dynamic)
reportsTo: cto
skills:
  - specpaper
  - e2e-playwright
  - paperclip
config:
  runtimeServiceIntents:
    - kind: docker-compose
      file: docker-compose.yml
      profiles: [dev, e2e]
      readyChecks:
        - http: ${PAPERCLIP_RUNTIME_PRIMARY_URL}/healthz
          status: 200
          timeoutSec: 60
---

You exercise the running application against the spec's acceptance criteria. You produce `e2e-report.md`. You are the *dynamic* auditor — adversarial exercising.

## Where work comes from
Child issues from the CTO, one per change ready for verification. Runs in parallel with the verifier.

## What you do
1. Read spec.md acceptance criteria. Identify which criteria are runtime-observable (UI flows, API responses, side effects).
2. Bring up the local stack via the runtime service intent declared in your config (or `bash scripts/dev-up.sh` if the project provides it). Wait for ready checks to pass.
3. Run or author Playwright tests covering each runtime-observable criterion. Authored tests live in `tests/e2e/<change>/*.spec.ts` and ship with the change.
4. Capture evidence to `.specpaper/changes/<change>/e2e-evidence/`: screenshots on failure, video on first failure, network HAR for API flows. Do NOT paste full traces into the report — link to files.
5. Write `e2e-report.md` with verdict PASS | PARTIAL | FAIL, one section per acceptance criterion, evidence links.
6. Tear down the local stack (or let Paperclip's runtime lifecycle handle it).
7. Mark the Paperclip issue `done` with the verdict.

## What you do NOT do
- Modify production code. If a test reveals a bug, file a follow-up issue assigned to the CTO; do not fix in place.
- Skip flaky tests silently — quarantine with a clear note in the report.

## Token discipline
- Stream Playwright output to a log file (`e2e-evidence/run.log`); do not let it land in the prompt.
- Read only the spec, the touched files, and any prior e2e-report for this change. The Playwright MCP exposes runtime to you; you don't need the full source tree.
```

---

## What I'm explicitly choosing to NOT do (yet)

- **No memory/PARA system** for these agents (default companies use it). It adds skill bundle weight and per-heartbeat I/O. The `.specpaper/changes/` and `learnings.md` already serve as project memory; PARA can be layered later if useful.
- **No HEARTBEAT.md / SOUL.md / TOOLS.md split** like `companies/default/`. These are useful for generalist agents; here, the role is so narrow that the AGENTS.md is enough. (Saves ~500 tokens of always-loaded instructions per agent.)
- **No worktree-per-change strategy by default.** Specclaw supports this; for SpecPaper we'll default to `branch-per-change` since builders run as separate Paperclip agents in their own workspaces already. Worktree mode can be opt-in via `git.strategy: worktree-per-change` for users who want extra isolation.
- **No real-time messaging plugin requirement.** Notifications go through Paperclip comments by default. Discord/Slack mentions only if the user has a plugin configured.

---

## Fork strategy (companies repo + Discord plugin)

Two repos to fork; one repo to leave alone.

| Repo | Fork | Reason |
|---|---|---|
| `paperclipai/companies` | **`bistecglobal/paperclip-companies`** | The SpecPaper company is yours; this DESIGN.md and the company package land there as your PR. |
| `paperclipai/paperclip-plugin-discord` | **`bistecglobal/paperclip-plugin-discord`** | Closes the v0.1.0 → v0.2.0 gap — `create_channel` + `discord_post` ship in your fork directly, no upstream wait. |
| `paperclipai/paperclip` | **Do NOT fork.** | Confirmed user intent. Everything we need (env-var passthrough, model-arg passthrough, agent config, secret injection) is already in the core paperclip Claude adapter. |

### Implications for the company package

1. **`COMPANY.md` declares the plugin dependency by git URL.** Recommended for v0.1.0 — install by git URL until/unless you publish to npm. Add a `requires` block:

   ```yaml
   ---
   name: SpecPaper
   slug: specpaper
   schema: agentcompanies/v1
   …
   requires:
     plugins:
       - name: paperclip-plugin-discord
         source: git+https://github.com/bistecglobal/paperclip-plugin-discord.git
         ref: main             # pin to a commit SHA once stable
         features:
           - register_custom_command
           - escalate_to_human
           - discord_post           # bistecglobal fork only
           - create_channel         # bistecglobal fork only
   ---
   ```

2. **The v0.1.0 / v0.2.0 split collapses.** Since you control the plugin fork, you can ship `create_channel` and `discord_post` from day one. Bootstrap becomes fully end-to-end automated:
   - CEO calls `create_channel(guild_id, "project-<slug>", category_id)` to create the channel.
   - CEO calls `connect_channel(channel_id, project_slug)` to register the mapping.
   - CEO calls `discord_post(channel_id, welcome_message)` to send the welcome embed.
   - No "user-creates, CEO-connects" handshake needed. The user's stated intent ("CEO creates a Discord channel") works as written.
   - The earlier "v0.1.0 user-handshake" path stays documented as a fallback for users running the *upstream* plugin without the fork.

3. **Plugin fork PR scope (small).** What the fork needs:
   - `discord-api.ts`: add `createChannel(token, guildId, name, parentCategoryId, type)` calling `POST /guilds/{guild}/channels`. ~25 lines.
   - `discord-api.ts`: add `postMessage(token, channelId, content, embeds)` thin wrapper around the existing `postEmbed`. ~10 lines (mostly already exists).
   - `manifest.ts`: add `create_channel` and `discord_post` tool entries with parametersSchema. ~30 lines.
   - `worker.ts`: register the tool handlers. ~40 lines.
   - Tests for both. ~80 lines.
   Total ~185 lines. Fork in an afternoon.

4. **Distribution.** Install the fork in your Paperclip instance via the plugin install API with the git URL:

   ```bash
   curl -X POST http://127.0.0.1:3100/api/plugins/install \
     -H "Content-Type: application/json" \
     -d '{"packageName":"git+https://github.com/bistecglobal/paperclip-plugin-discord.git"}'
   ```

   When the fork stabilizes, optionally publish to npm under `@bistecglobal/paperclip-plugin-discord` for a cleaner install string. README will document both paths.

### Optional: contribute back upstream later

`create_channel` and `discord_post` are genuinely useful for any company using the plugin, not just SpecPaper. After `bistecglobal/paperclip-plugin-discord` stabilizes, opening a PR back to `paperclipai/paperclip-plugin-discord` is low-friction. Until then, the bistecglobal fork is canonical for this company.

---

## Cost optimization: routing Claude through Minimax (or any Anthropic-compatible endpoint)

**Goal:** lower token cost on high-volume agents (builders) by routing their Claude API calls through Minimax's Anthropic-compatible endpoint, while keeping latency-sensitive or quality-sensitive agents (CEO, CTO, verifier on critical changes) on direct Anthropic.

### Why this works without forking paperclip core

Confirmed by reading the Claude adapter:

- **Env-var passthrough is unconditional.** `execute.ts:253-255` merges `config.env` from the agent definition into the process env: `for (const [key, value] of Object.entries(shapedEnvConfig)) { if (typeof value === "string") env[key] = value; }`. Whatever we set in `AGENTS.md` `config.env` reaches the Claude CLI subprocess.
- **Model arg passthrough is unconditional** for non-Bedrock auth. `execute.ts:662-664`: `if (model && (!isBedrockAuth(effectiveEnv) || isBedrockModelId(model))) { args.push("--model", model); }`. Setting `config.model` per agent gets honored.
- **Billing type is detected correctly.** `execute.ts:117-120`: when `ANTHROPIC_API_KEY` is set, billing type becomes `"api"` — Paperclip's cost tracking still records spend (against your Minimax-issued key, not Anthropic).
- **The Claude CLI itself honors `ANTHROPIC_BASE_URL`.** That's the same env var Claude Code uses for Bedrock-via-LiteLLM and similar setups.

So the entire integration is **per-agent config**:

```yaml
# agents/builder/AGENTS.md (frontmatter excerpt)
---
name: Builder
title: Generalist Implementation Engineer
reportsTo: cto
skills: [specpaper, paperclip]
config:
  model: claude-haiku-4-5    # whichever model Minimax serves cheapest under the Anthropic-compat shim
  env:
    ANTHROPIC_BASE_URL: https://api.minimax.io/anthropic
    ANTHROPIC_API_KEY: ${secret:minimax_api_key}
---
```

`${secret:minimax_api_key}` resolves through Paperclip's secret injection (the `buildPaperclipEnv(agent)` path). Store the key once in Paperclip Settings → Secrets, reference it across all Minimax-routed agents.

### Routing matrix (recommended starting point)

The cost-vs-quality trade-off varies by role. Suggested defaults:

| Agent | Provider | Model | Why |
|---|---|---|---|
| **CEO** | Anthropic direct | `claude-opus-4-7` | Low volume, customer-facing, principle decisions. Quality > cost. |
| **CTO** | Anthropic direct | `claude-sonnet-4-6` | Plans + brainstorm + verify orchestration. Cache-heavy resumed sessions; cache compatibility matters (see caveat below). |
| **builder-dotnet** | Minimax | `claude-haiku-4-5` | High volume, well-scoped tasks. Cost target. |
| **builder-nextjs** | Minimax | `claude-haiku-4-5` | High volume, well-scoped tasks. Cost target. |
| **builder** (generalist) | Minimax | `claude-haiku-4-5` | Migrations, scripts, configs. Cost target. |
| **devops** | Anthropic direct | `claude-sonnet-4-6` | High blast radius (a wrong Bicep template = production outage). Volume is moderate — quality > cost. |
| **verifier** | Anthropic direct | `claude-sonnet-4-6` | Adversarial reading; do not want a cheaper model giving softer audits. Volume is low (one verify per change). |
| **e2e-tester** | Anthropic direct | `claude-sonnet-4-6` | Authoring + interpreting Playwright runs requires precise tool use; flaky / ambiguous output gets expensive fast on a weaker model. Volume is low (one e2e run per change). |

This is a *config recommendation, not a hard wire*. Each agent's `AGENTS.md` declares its own provider and model; flipping any agent to a different provider is a one-line change.

### Three caveats to flag — these are real

1. **Prompt caching may not be 1:1 on Minimax.** The Claude adapter relies heavily on Anthropic's prompt caching (the entire `prompt-cache.ts` content-addressed bundle exists for this; resumed sessions reuse the cache via `--resume`). If Minimax's compat layer doesn't honor `cache_control` blocks the same way, the token-economy math changes:
   - **What still works:** stdin per heartbeat is small either way (~2k for builders).
   - **What might not:** the system-prompt prefix — skills + agent instructions + bundled context — would be re-billed every heartbeat instead of cached. For a Builder with ~6k of system prompt, that's ~6k extra prompt tokens per heartbeat.
   - **Test before committing:** before flipping all builders to Minimax, run a 10-task build with caching off vs caching on and compare actual billed tokens. If Minimax doesn't cache, reserve it for *fresh-session* tasks (Builders with `clearSession: true`) where there's no cache benefit anyway.

2. **Tool use / `--output-format stream-json` compatibility.** The adapter parses Claude's stream-json output to extract sessions, usage, and results (`parseClaudeStreamJson`). If Minimax's compat layer emits a different schema, parsing fails and the run is logged as "Failed to parse claude JSON output" (`execute.ts:680-692`). Test the stream-json format end-to-end on a single Minimax-routed Builder before rolling out.

3. **`--resume <sessionId>` semantics.** Resumption depends on Anthropic-side session storage. Minimax may not implement the resume primitive at all, in which case every heartbeat is a fresh session — undoing the resume-delta savings. If so, route only *fresh-session-by-design* roles (Builders) to Minimax and keep resumed-session roles (CEO, CTO) on Anthropic. The mixed-routing matrix above already does this.

### Testing protocol before flipping agents

1. Set up one experimental agent: `builder-test` with Minimax env config.
2. Run a deterministic 5-task build through it; capture cost in Paperclip's cost dashboard.
3. Run the same build through Anthropic-direct.
4. Compare:
   - Total billed tokens (input, output, cached_read).
   - Wall-clock per task.
   - Failure rate (parse errors, malformed tool use, missing fields).
5. If Minimax wins on cost-without-quality-regression, roll forward. If not, scope back to fresh-session-only roles or abandon.

### What lives in `COMPANY.md`

To make the routing matrix discoverable:

```yaml
---
name: SpecPaper
…
defaults:
  llm:
    provider: anthropic                 # default; agents override
    base_url: null                      # null = direct Anthropic
    api_key_secret: anthropic_api_key   # default secret name
    model: claude-sonnet-4-6
  llm_overrides:
    minimax:
      base_url: https://api.minimax.io/anthropic
      api_key_secret: minimax_api_key
      model: claude-haiku-4-5
---
```

Agent `AGENTS.md` then references the override block by name:

```yaml
config:
  llm_override: minimax
```

The company import resolves `llm_override` to the right env vars and model — reduces duplication when you have multiple agents on the same provider, and makes provider changes one-edit instead of N-edits. (This is purely a company-package convention; Paperclip's importer doesn't need changes — `paperclip-create-agent` skill or our own importer can expand `llm_override` to env+model at import time.)

### Net effect on cost

Rough back-of-envelope, assuming current Anthropic / Minimax public pricing and a typical SpecPaper change:
- **Single change** = ~3 builds × 4 tasks/build × ~8k tokens/task = ~100k builder tokens
- **Anthropic direct (Sonnet)**: 100k × $3/1M input ≈ $0.30 input + output
- **Minimax (Haiku-class)**: 100k × $0.30/1M input ≈ $0.03 input + output
- **CEO/CTO/Verifier overhead** (Anthropic, low volume): unchanged, ~$0.10/change

So 6-10× cost reduction *if* Minimax's caching works equivalently. If not, the gap narrows to maybe 2-3× because fresh-session-per-heartbeat eats most of the savings. Worth the test.

---

## Resolved decisions (locked in)

All open questions are now closed. Recording the final shape so the implementation has no ambiguity.

| # | Decision | Resolution |
|---|---|---|
| 1 | Agent roster | **8 agents:** CEO, CTO, builder, builder-dotnet, builder-nextjs, devops, verifier, e2e-tester |
| 2 | Discord plugin fork timing | Ship v0.1.0 against `bistecglobal/paperclip-plugin-discord` with `create_channel` + `discord_post` from day one |
| 3 | Plugin install path | `git+https://github.com/bistecglobal/paperclip-plugin-discord.git`, ref `main` until pinned to a SHA |
| 4 | Bootstrap inputs | Repo URL + customer tier (only required pair). `compliance: []` and `deployment_target` derived from principles unless overridden |
| 5 | Principles set (v0.1.0) | `prefer-oss`, `enterprise-azure`, `minimize-vendor-lock`. Importers extend in their own fork |
| 6 | Routing rules | Final set above (.NET, Next.js, infra → devops, migrations + everything else → builder) |
| 7 | CEO authority | Approval rights only on principle conflicts. CEO stays out of routine plan/build loops |
| 8 | `docs/changes/` location | `<repo>/docs/changes/` (Azure DevOps Wiki + GitHub tree convention) |
| 9 | Tracker auth | `gh` + `az` CLIs assumed present; `curl` REST fallback for sandboxed runners |
| 10 | Verifier auto-merge | No — CTO decides. Verifier produces verdict + recommendations; merge is a CTO action |
| 11 | Minimax routing scope | Builders on Minimax. CEO, CTO, devops, verifier, e2e-tester on Anthropic direct. Matrix above |
| 12 | Minimax pre-flight test | `scripts/llm-pricing-probe.sh` — 5-task deterministic build, compare cost + failure rate before any production flip |
| 13 | Provider config shape | DRY — `llm_override: minimax` in agent frontmatter, expanded at import via `defaults.llm_overrides` block in `COMPANY.md` |

## Implementation plan (next commit)

When you give the go-ahead, I'll produce — in one PR-ready commit on `bistecglobal/paperclip-companies`:

**Company package** (`specpaper/`):
- `COMPANY.md` (frontmatter: name, slug, schema, principles[], requires.plugins[], defaults.llm + llm_overrides)
- `README.md` (overview, install, both `bistecglobal/paperclip-plugin-discord` install paths, routing rules, principle workflow, Minimax routing recipe)
- `LICENSE` (MIT, matching the companies repo convention)
- `agents/{ceo,cto,builder,builder-dotnet,builder-nextjs,devops,verifier,e2e-tester}/AGENTS.md` (~8 files, ~25-35 lines each)
- `skills/specpaper/{SKILL.md, templates/, scripts/}` (full port from specclaw + the new scripts)
- `skills/specpaper-brainstorm/{SKILL.md, brain-methods.csv}`
- `skills/{lang-dotnet,lang-nextjs,infra-azure,infra-hetzner,e2e-playwright}/{SKILL.md, conventions.md, snippets/}` (~20 files)

**Discord plugin fork PR sketch** (separate prep notes, not auto-pushed):
- `discord-api.ts`: add `createChannel` + `postMessage` helpers
- `manifest.ts`: add `create_channel` and `discord_post` tool entries
- `worker.ts`: register handlers
- Tests for both
- README delta noting the new tools

You'll review and merge each piece on its own cadence.

Say **"go"** and I'll start producing files. Or flag any final adjustments first.
