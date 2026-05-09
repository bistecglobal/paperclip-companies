---
name: specpaper
description: "Spec-driven development lifecycle for Paperclip companies. Manages propose → plan → brainstorm → build → audit (static + dynamic) → archive across .NET / Next.js / Postgres projects with Azure / Hetzner deployment. Tracker-agnostic (GitHub Issues + Azure DevOps Work Items) with mandatory in-repo docs."
---

# SpecPaper — Spec-Driven Development for Paperclip

## Overview

SpecPaper brings structured, spec-driven development to a Paperclip agent team. It manages the full lifecycle of a change from idea to ship, using Paperclip child issues for delegation and the bistecglobal Discord plugin for the human surface.

The lifecycle: **propose → optionally brainstorm → plan → build (waves) → audit (verifier ∥ e2e-tester) → archive**.

## Project layout (per-project)

When initialized (`.specpaper/` exists in project root):

```
.specpaper/
├── config.yaml          # Project configuration (tracker, routing rules, tooling)
├── project.yaml         # Paperclip project metadata (id, slug, repo, tracker)
├── STATUS.md            # Project dashboard (auto-generated)
├── patterns.md          # Recurring pattern registry (cross-change)
├── decisions/           # CEO decision records (principle-conflict resolutions)
└── changes/
    ├── <change-name>/
    │   ├── proposal.md         # Problem + solution + scope
    │   ├── context.yaml        # customer_tier, compliance, deployment_target
    │   ├── brainstorm.md       # (optional) brainstorm session output
    │   ├── spec.md             # Requirements + acceptance criteria
    │   ├── design.md           # Technical approach + Principles applied
    │   ├── tasks.md            # Ordered tasks with status markers, agent routing
    │   ├── status.md           # Progress tracking
    │   ├── errors.md           # Build error journal (auto-generated on failures)
    │   ├── learnings.md        # Build learnings (spec gaps, patterns, insights)
    │   ├── verify-report.md    # Static audit (verifier)
    │   ├── e2e-report.md       # Dynamic audit (e2e-tester)
    │   ├── e2e-evidence/       # Screenshots, traces, HARs (gitignored)
    │   └── .task-context-*.md  # Per-task agent context (gitignored)
    └── archive/                # Completed changes
```

The **human-readable subset** (proposal, brainstorm, spec, design, verify-report, e2e-report) is mirrored to `<repo>/docs/changes/<change>/` on every lifecycle stage transition. The docs subfolder is **always** written, regardless of tracker choice.

## Commands

The user triggers commands conversationally in Discord (via `!propose`, `!plan`, etc.) or directly to the CTO. Recognize these patterns:

### `specpaper init`

**Trigger:** internal — run by `bootstrap.sh`, rarely invoked manually.

1. Create `.specpaper/` directory structure
2. Generate `config.yaml` from template (`templates/config.yaml`)
3. Generate `project.yaml` with paperclip project metadata
4. Create initial `STATUS.md`
5. Create `.gitignore` entries for `e2e-evidence/`, `.task-context-*`, `archive/`

### `specpaper propose "<idea>"`

**Trigger:** "specpaper propose", "!propose", "propose a change"

1. Slugify the idea → `<change-name>`
2. Create `.specpaper/changes/<change-name>/`
3. Generate `proposal.md` from template (problem, proposed solution, scope, impact, open questions)
4. Generate `context.yaml` with defaults inherited from `project.yaml`
5. Update `STATUS.md`
6. **Tracker sync:** `bash skills/specpaper/scripts/tracker-sync.sh create .specpaper <change>` — creates a GitHub Issue or Azure DevOps Work Item depending on `tracker.kind`. Skipped when `tracker.kind: none`.
7. **Paperclip:** create a Paperclip issue titled `Proposal: <change>` with this proposal as the body. Plugin auto-posts to the project's Discord channel as an `issue-created` embed.
8. **Docs sync:** `bash skills/specpaper/scripts/docs-sync.sh .specpaper <change>` — copies `proposal.md` to `<repo>/docs/changes/<change>/proposal.md` and updates `<repo>/docs/changes/index.md`.

### `specpaper brainstorm <change> [--technique=<name>]`

**Trigger:** "specpaper brainstorm", "!brainstorm"

Run by the CTO when the proposal scope is unclear or the solution space is wide. Uses the `specpaper-brainstorm` skill.

1. Validate proposal exists.
2. Read `COMPANY.md` principles (used as soft scoring biases).
3. Pick a technique from `skills/specpaper-brainstorm/brain-methods.csv` (user-selected via `--technique`, AI-recommended otherwise).
4. Generate ≥50 ideas under the anti-bias protocol (shift creative domain every 10 ideas; force orthogonal categories).
5. Surface top 5 with rationale; flag principle violations.
6. Write `.specpaper/changes/<change>/brainstorm.md` with: goal, technique used, raw ideas (numbered), top 5 with rationale, recommended next steps that become spec input.
7. **Docs sync:** mirror to `<repo>/docs/changes/<change>/brainstorm.md`.
8. **Discord:** post the top-5 summary to the project channel via the plugin's `discord_post` tool.

### `specpaper plan <change>`

**Trigger:** "specpaper plan", "!plan"

1. **Validate:** `bash skills/specpaper/scripts/validate-change.sh .specpaper <change> plan`. Requires proposal.md.
2. Read the proposal + brainstorm.md (if present) + context.yaml.
3. Read `COMPANY.md` principles. Identify which apply given context (`when: default` always; conditional `when:` evaluated against context fields).
4. Analyze existing codebase (file structure, patterns, dependencies in scope).
5. Generate:
   - `spec.md` — functional requirements, acceptance criteria (mark each as runtime-observable or static-only), edge cases.
   - `design.md` — technical approach, architecture, file changes map, **`## Principles applied` section** (every applicable principle with `[x]`/`[ ]` and one-line rationale; conflicts named explicitly).
   - `tasks.md` — ordered tasks with dependencies, file lists, **`Agent:` field** routing each task to the right builder (`parse-tasks.sh` infers from globs if omitted).
6. Set `context.yaml.deployment_target` if any infra task is planned (driven by principles).
7. Update STATUS.md.
8. **Tracker sync:** `tracker-sync.sh update .specpaper <change>` — adds the task checklist to the GitHub Issue or AzDo Work Item.
9. **Docs sync:** mirror spec.md + design.md to `<repo>/docs/changes/<change>/`.

### `specpaper build <change>`

**Trigger:** "specpaper build", "!build"

This is where the orchestration happens.

#### Step 0 — Validate

```bash
bash skills/specpaper/scripts/validate-change.sh .specpaper <change> build
```

Requires spec.md, design.md (with Principles applied section), tasks.md.

#### Step 1 — Setup

```bash
bash skills/specpaper/scripts/build.sh setup .specpaper <change>
```

Returns JSON: `branch`, `parallel_tasks`, `git.strategy`, total task and wave counts.

**Branch strategy:**
- `branch-per-change` (default) — single branch `specpaper/<change>` for all task work.
- `worktree-per-change` (opt-in) — isolated worktree at `.specpaper/worktrees/<change>/`. Each builder agent's Paperclip workspace sets cwd to the worktree.
- `direct` — commits straight to default branch (only sane for trivial changes).

#### Step 2 — Parse tasks

```bash
bash skills/specpaper/scripts/parse-tasks.sh --status pending .specpaper/changes/<change>/tasks.md
```

Outputs JSON: `[{"id":"T1","title":...,"wave":1,"depends":[],"files":[...],"agent":"builder-dotnet","estimate":"small","status":"pending"}, ...]`.

For retries:

```bash
bash skills/specpaper/scripts/parse-tasks.sh --status failed .specpaper/changes/<change>/tasks.md
bash skills/specpaper/scripts/update-task-status.sh .specpaper/changes/<change>/tasks.md <TASK_ID> pending
```

#### Step 3 — Wave loop (Paperclip child-issue delegation)

For each wave number (1, 2, 3...):

**a. Filter tasks for this wave:**

```bash
bash skills/specpaper/scripts/parse-tasks.sh --wave N --status pending .specpaper/changes/<change>/tasks.md
```

If no tasks, build is complete — skip to Step 4.

**b. For each task in the wave (up to `parallel_tasks` from config):**

1. **Build context payload to a workspace file:**
   ```bash
   bash skills/specpaper/scripts/build-context.sh .specpaper <change> <TASK_ID> > .specpaper/changes/<change>/.task-context-<TASK_ID>.md
   ```

2. **Mark in-progress:**
   ```bash
   bash skills/specpaper/scripts/update-task-status.sh .specpaper/changes/<change>/tasks.md <TASK_ID> in_progress
   ```

3. **Create Paperclip child issue assigned to the task's agent:**
   ```
   POST /api/companies/{companyId}/issues
   {
     "projectId": "<from project.yaml>",
     "parentId": "<change root issue id>",
     "title": "<TASK_ID> — <task title>",
     "description": "Read .specpaper/changes/<change>/.task-context-<TASK_ID>.md for context. Modify only the files listed there.",
     "assigneeAgentId": "<agent name from tasks.md or routing rules>",
     "labels": ["specpaper", "task", "<change>"],
     "blockerIssueIds": [<previous-wave issue ids>]
   }
   ```
   Capture the returned issue id; record in `.specpaper/changes/<change>/.wave-<N>-issues.json`.

**c. End the heartbeat in `in_review` on the change issue.**

Paperclip's blocker dependencies wake the CTO when all wave-N issues close. Do NOT poll. The next heartbeat reads `.wave-<N>-issues.json`, checks each issue's status, and processes results.

**d. Process completed wave (next heartbeat):**

For each issue that is `done`:

1. `update-task-status.sh ... complete`
2. If previously failed (was `[!]`): `bash skills/specpaper/scripts/log-error.sh .specpaper <change> --resolve <task_id>`
3. The Builder already committed via `build.sh commit`. Plugin already posted `issue-done`. No extra Discord post needed.

For each issue that is `blocked` or had an `agent-error` event:

1. `update-task-status.sh ... failed`
2. `bash skills/specpaper/scripts/log-error.sh .specpaper <change> <task_id> <wave> <agent_label> "<failure summary>"`
3. Mark all dependent tasks in later waves as `failed`
4. `bash skills/specpaper/scripts/tracker-sync.sh comment .specpaper <change> "❌ Task <task_id> failed: <summary>"`

**e. Tracker + docs sync at end of wave:**

```bash
bash skills/specpaper/scripts/tracker-sync.sh update .specpaper <change>
bash skills/specpaper/scripts/docs-sync.sh .specpaper <change>
```

**f. Repeat** for the next wave until no pending tasks remain.

#### Step 4 — Finalize

```bash
bash skills/specpaper/scripts/build.sh finalize .specpaper <change>
```

Runs `tooling.test_command` against the change branch and prepares the merge per `git.strategy`.

#### Step 5 — Post-build review (auto-logged)

If `automation.post_build_review: true`:

1. **Scope deviation:** files changed-but-not-declared are auto-logged via `log-learning.sh design_gap medium`.
2. **Pattern scan:** `bash skills/specpaper/scripts/detect-patterns.sh .specpaper scan <change>`.
3. Patterns with recurrence ≥ 3 are flagged for elevation to `COMPANY.md` or `lang-*/conventions.md`.

#### Step 6 — Trigger audits (parallel)

Create **two** Paperclip child issues, both blocked by the last build wave's issues:

- One assigned to `verifier` — body points to verify entrypoint
- One assigned to `e2e-tester` — body points to e2e entrypoint

End the heartbeat in `in_review`. Paperclip wakes the CTO when both audit issues close.

### `specpaper verify <change>`

**Trigger:** Verifier agent only. Static audit. See `agents/verifier/AGENTS.md`. Produces `verify-report.md`.

The CTO does not invoke this directly — it is delegated via a child issue assigned to the verifier.

### E2E (no separate command on the CTO side)

The e2e-tester is delegated via a child issue at the same time as the verifier. It produces `e2e-report.md`. See `agents/e2e-tester/AGENTS.md`.

### `specpaper learn <change> "<insight>"`

```bash
bash skills/specpaper/scripts/log-learning.sh .specpaper <change> <category> <priority> "<detail>" ["<action>"]
```

Categories: `spec_gap` | `design_gap` | `pattern` | `best_practice` | `agent_issue`
Priorities: `low` | `medium` | `high`

```bash
bash skills/specpaper/scripts/log-learning.sh .specpaper <change> --list
bash skills/specpaper/scripts/log-learning.sh .specpaper <change> --promote <id>
```

### `specpaper patterns`

```bash
bash skills/specpaper/scripts/detect-patterns.sh .specpaper scan <change>
bash skills/specpaper/scripts/detect-patterns.sh .specpaper list [--min-recurrence N]
bash skills/specpaper/scripts/detect-patterns.sh .specpaper promote <pat-id>
```

Patterns with ≥3 occurrences are flagged ⚠️ — elevate to `COMPANY.md` principles or `lang-*/conventions.md`.

### `specpaper status`

**Trigger:** "!status", "specpaper status"

```bash
bash skills/specpaper/scripts/update-status.sh .specpaper
```

Regenerates `STATUS.md`. CTO can post a Discord summary by calling the plugin's `discord_post` tool with a digest.

### `specpaper archive <change>`

**Trigger:** "!archive", "specpaper archive"

1. **Validate:** `validate-change.sh .specpaper <change> archive`. Requires verify PASS + e2e PASS.
2. Move to `.specpaper/changes/archive/YYYY-MM-DD-<change>/`.
3. Update `STATUS.md`.
4. **Tracker sync:** `tracker-sync.sh close .specpaper <change>`.
5. **Docs:** `docs/changes/<change>/` stays in place permanently — that is the audit trail. Update `docs/changes/index.md`.
6. Optionally create a git tag.

## Task format in `tasks.md`

```markdown
## Tasks

### Wave 1 (no dependencies)
- [ ] `T1` — Add idempotency_keys table
  - Files: `db/migrations/20260601_idempotency_keys.sql`
  - Agent: builder
  - Estimate: small

### Wave 2 (depends on Wave 1)
- [ ] `T2` — Add idempotency middleware
  - Files: `src/Api/Middleware/IdempotencyMiddleware.cs`, `src/Api/Program.cs`
  - Agent: builder-dotnet
  - Depends: T1
  - Estimate: medium

### Wave 3 (depends on Wave 2)
- [ ] `T3` — Wire idempotency-key header on the checkout form
  - Files: `apps/web/app/checkout/page.tsx`, `apps/web/lib/idempotency.ts`
  - Agent: builder-nextjs
  - Depends: T2
  - Estimate: small
```

Status markers:
- `[ ]` — pending
- `[~]` — in progress
- `[x]` — complete
- `[!]` — failed (needs remediation)

If `Agent:` is omitted, `parse-tasks.sh` infers from the file list using `routing.rules` in `config.yaml`.

## Tracker abstraction (`tracker-sync.sh`)

One script handles GitHub and Azure DevOps. Dispatches on `tracker.kind`:

| Action | GitHub (`gh` CLI) | Azure DevOps (`az` CLI) |
|---|---|---|
| `create` | `gh issue create --title --body --label specpaper` | `az boards work-item create --type "User Story" --title --description` |
| `update` | `gh issue edit <num> --body` | `az boards work-item update --id <id> --description` |
| `comment` | `gh issue comment <num> --body` | `az boards work-item update --id <id> --discussion` |
| `close` | `gh issue close <num>` | `az boards work-item update --id <id> --state Done` |

Auth: `GITHUB_TOKEN` / `gh auth status` for GitHub; `AZURE_DEVOPS_EXT_PAT` / `az login` for Azure DevOps. CLI absence falls back to raw REST via `curl`.

The change's tracker reference (issue number / work item ID) is stored in `.specpaper/changes/<change>/.tracker-ref` after `create`.

## Docs sync (`docs-sync.sh`)

Mirrors the human-readable subset to `<repo>/docs/changes/<change>/`:

| File | Mirrored on |
|---|---|
| `proposal.md` | `propose` |
| `brainstorm.md` | `brainstorm` |
| `spec.md` | `plan` |
| `design.md` | `plan` |
| `verify-report.md` | `verify` |
| `e2e-report.md` | e2e-tester completion |

Maintains `docs/changes/index.md`.

**Always on.** If `docs-sync.sh` fails, the lifecycle stage that triggered it is marked `blocked` — silent skip is not allowed.

## Configuration reference

See `templates/config.yaml` for the full schema. Key sections:

- `tracker.kind` — `github | azure-devops | none`
- `tracker.github.repo`, `tracker.azure_devops.{organization, project, work_item_type}`
- `routing.rules` — glob → agent mapping for build delegation
- `tooling.{lint_command, test_command, format_command}` — quality gates
- `git.strategy` — `branch-per-change | worktree-per-change | direct`
- `automation.{auto_verify, post_build_review, max_tasks_per_run}`
- `docs.{enabled, path, index}` — docs subfolder configuration

## Best practices

1. **Keep proposals focused** — one change per proposal, small scope.
2. **Brainstorm only when needed** — for clear requests, skip straight to plan.
3. **Cite principles explicitly** — design.md must reference every applicable principle.
4. **Wave-based execution** — group independent tasks; let Paperclip blockers gate next wave.
5. **Fresh context per task** — each Builder reads `.task-context-<id>.md` only; never carries context across tasks.
6. **Verify early on remediation** — re-run audits on partial fixes; don't accumulate debt.
7. **In-repo docs are not optional** — they are the floor of the audit trail.
