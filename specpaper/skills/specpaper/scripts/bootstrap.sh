#!/usr/bin/env bash
# bootstrap.sh — Bootstrap a SpecPaper-managed project.
#
# Run by the CEO agent on a new project request. Clones the repo, creates the
# Paperclip project, creates the dedicated Discord channel via the forked
# bistecglobal/paperclip-plugin-discord plugin, registers !propose/!plan/etc.
# custom commands, and writes .specpaper/project.yaml.
#
# Usage:
#   bootstrap.sh <repo-url> [--name "<name>"] [--customer-tier <tier>]
#                          [--compliance "<csv>"] [--deployment-target <target>]
#
# Env required:
#   PAPERCLIP_API_KEY                — already set by the Paperclip Claude adapter
#   PAPERCLIP_API_URL                — e.g. http://127.0.0.1:3100
#   PAPERCLIP_COMPANY_ID             — UUID of the SpecPaper company (set per-instance)
#
# Env required for Discord channel creation (skipped cleanly if any are missing):
#   DISCORD_BOT_TOKEN                — bot token (kept out of process listings; never echoed)
#   DISCORD_GUILD_ID                 — server (guild) ID
#   DISCORD_PROJECTS_CATEGORY_ID     — category channel ID under which #project-<slug> is created
#
# Dependencies: bash, git, curl, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<'EOF'
Usage: bootstrap.sh <repo-url> [options]

Options:
  --name "<name>"             Human-friendly project name (defaults to repo basename)
  --customer-tier <tier>      enterprise | smb | internal (default: internal)
  --compliance "<csv>"        comma-separated, e.g. "sox,hipaa,gdpr"
  --deployment-target <t>     azure | hetzner (default: derived from customer-tier)
EOF
  exit "${1:-0}"
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]] && usage

REPO_URL="$1"; shift
NAME=""
CUSTOMER_TIER="internal"
COMPLIANCE=""
DEPLOYMENT_TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --customer-tier) CUSTOMER_TIER="$2"; shift 2 ;;
    --compliance) COMPLIANCE="$2"; shift 2 ;;
    --deployment-target) DEPLOYMENT_TARGET="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; usage 1 ;;
  esac
done

# Derive sensible defaults
SLUG="$(basename "$REPO_URL" .git | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')"
NAME="${NAME:-$SLUG}"

if [[ -z "$DEPLOYMENT_TARGET" ]]; then
  if [[ "$CUSTOMER_TIER" == "enterprise" ]]; then
    DEPLOYMENT_TARGET="azure"
  else
    DEPLOYMENT_TARGET="hetzner"
  fi
fi

# Tracker dispatch from URL
TRACKER_KIND="none"
TRACKER_ORG=""
TRACKER_PROJECT=""
case "$REPO_URL" in
  *github.com*)
    TRACKER_KIND="github"
    TRACKER_ORG="$(echo "$REPO_URL" | sed -E 's|.*github.com[:/]([^/]+)/.*|\1|')"
    TRACKER_PROJECT="$(echo "$REPO_URL" | sed -E 's|.*github.com[:/][^/]+/([^/.]+).*|\1|')"
    ;;
  *dev.azure.com*|*visualstudio.com*)
    TRACKER_KIND="azure-devops"
    TRACKER_ORG="$(echo "$REPO_URL" | sed -E 's|(https?://[^/]+/[^/]+).*|\1|')"
    TRACKER_PROJECT="$(echo "$REPO_URL" | sed -E 's|.*/([^/]+)/_git/.*|\1|')"
    ;;
esac

WORKSPACE_DIR="${SPECPAPER_WORKSPACE_ROOT:-$HOME/.paperclip/workspaces}/$SLUG"
mkdir -p "$(dirname "$WORKSPACE_DIR")"

# 1. Clone (idempotent — re-bootstrap on existing workspace updates rather than re-clones)
if [[ -d "$WORKSPACE_DIR/.git" ]]; then
  echo "[bootstrap] Workspace exists at $WORKSPACE_DIR — fetching updates."
  git -C "$WORKSPACE_DIR" fetch --all --prune
else
  echo "[bootstrap] Cloning $REPO_URL → $WORKSPACE_DIR"
  git clone "$REPO_URL" "$WORKSPACE_DIR"
fi

DEFAULT_BRANCH="$(git -C "$WORKSPACE_DIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)"

cd "$WORKSPACE_DIR"

# 2. Create Paperclip project
PAPERCLIP_API_URL="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"
PROJECT_BODY="$(jq -n \
  --arg name "$NAME" \
  --arg slug "$SLUG" \
  --arg repoUrl "$REPO_URL" \
  --arg defaultBranch "$DEFAULT_BRANCH" \
  '{name: $name, slug: $slug, repoUrl: $repoUrl, defaultBranch: $defaultBranch}')"

if ! PROJECT_RESPONSE="$(curl -sf -X POST "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/projects" \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$PROJECT_BODY")"; then
  # Fallback: project may already exist; try to look it up by slug
  PROJECT_RESPONSE="$(curl -sf "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/projects?slug=$SLUG" \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" | jq '.items[0]')"
fi
PROJECT_ID="$(echo "$PROJECT_RESPONSE" | jq -r '.id')"
[[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]] && { echo "ERROR: failed to obtain Paperclip projectId" >&2; exit 1; }
echo "[bootstrap] Paperclip projectId: $PROJECT_ID"

# 3. Initialize SpecPaper (idempotent)
# init.sh expects the *project* directory, not the .specpaper directory.
if [[ ! -d ".specpaper" ]]; then
  bash "$SCRIPT_DIR/init.sh" "." "$NAME"
fi

# 4. Write project.yaml
cat > .specpaper/project.yaml <<EOF
project:
  id: "$PROJECT_ID"
  slug: "$SLUG"
  name: "$NAME"
  repo:
    url: "$REPO_URL"
    default_branch: "$DEFAULT_BRANCH"
  tracker:
    kind: "$TRACKER_KIND"
    organization: "$TRACKER_ORG"
    project: "$TRACKER_PROJECT"
  context:
    customer_tier: "$CUSTOMER_TIER"
    compliance: [$(echo "$COMPLIANCE" | sed 's/,/", "/g; s/^/"/; s/$/"/' | sed 's/""//')]
    deployment_target: "$DEPLOYMENT_TARGET"
  status: "active"
  created_at: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
echo "[bootstrap] Wrote .specpaper/project.yaml"

# 5. Update config.yaml with tracker info.
# Only patch the block that matches the detected tracker.kind to avoid
# polluting unrelated tracker config sections (the GH parser would otherwise
# write chan4lk/keyflow into both github and azure_devops blocks).
case "$TRACKER_KIND" in
  github)
    python3 - <<EOF
import re
p = ".specpaper/config.yaml"
text = open(p).read()
text = re.sub(r'kind:\s*"none"', 'kind: "$TRACKER_KIND"', text, count=1)
# Replace only inside the github: sub-block
def patch_github(m):
    block = m.group(0)
    block = re.sub(r'(repo:\s*)""', r'\1"$TRACKER_ORG/$TRACKER_PROJECT"', block, count=1)
    return block
text = re.sub(r'  github:\n(?:    .*\n)+', patch_github, text, count=1)
open(p, "w").write(text)
EOF
    ;;
  azure-devops)
    python3 - <<EOF
import re
p = ".specpaper/config.yaml"
text = open(p).read()
text = re.sub(r'kind:\s*"none"', 'kind: "$TRACKER_KIND"', text, count=1)
def patch_azdo(m):
    block = m.group(0)
    block = re.sub(r'(organization:\s*)""', r'\1"$TRACKER_ORG"', block, count=1)
    block = re.sub(r'(project:\s*)""', r'\1"$TRACKER_PROJECT"', block, count=1)
    return block
text = re.sub(r'  azure_devops:\n(?:    .*\n)+', patch_azdo, text, count=1)
open(p, "w").write(text)
EOF
    ;;
esac

# 6. Add gitignore entries
GITIGNORE=".gitignore"
touch "$GITIGNORE"
for entry in ".specpaper/changes/*/e2e-evidence/" ".specpaper/changes/*/.task-context-*" ".specpaper/worktrees/" ".specpaper/changes/archive/"; do
  grep -qxF "$entry" "$GITIGNORE" || echo "$entry" >> "$GITIGNORE"
done

# 7. Discord: create channel directly via Discord REST.
#
# Why not the plugin create_channel tool? Paperclip's plugin tool dispatcher
# (POST /api/plugins/tools/execute) requires a real runContext (live agentId
# + runId tied to an active agent run). A setup script invoked from a shell
# does not have that — only an in-flight CEO heartbeat does. So this script
# uses Discord REST directly when the bot token + guild + category are
# available in the environment, and skips channel creation cleanly otherwise.
DISCORD_CHANNEL_ID=""
if [[ -n "${DISCORD_BOT_TOKEN:-}" && -n "${DISCORD_GUILD_ID:-}" && -n "${DISCORD_PROJECTS_CATEGORY_ID:-}" ]]; then
  echo "[bootstrap] Creating Discord channel via Discord REST..."
  DISCORD_CREATE_BODY="$(jq -n \
    --arg name "project-$SLUG" \
    --arg topic "$NAME — managed by SpecPaper. Use !propose, !plan, !build, !verify, !archive, !status." \
    --arg parent "$DISCORD_PROJECTS_CATEGORY_ID" \
    '{name: $name, type: 0, topic: $topic, parent_id: $parent}')"

  DISCORD_CREATE_RESPONSE="$(curl -sf -X POST \
    "https://discord.com/api/v10/guilds/$DISCORD_GUILD_ID/channels" \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$DISCORD_CREATE_BODY" 2>/dev/null || echo '{}')"
  DISCORD_CHANNEL_ID="$(echo "$DISCORD_CREATE_RESPONSE" | jq -r '.id // empty')"

  if [[ -n "$DISCORD_CHANNEL_ID" ]]; then
    echo "[bootstrap] Channel created: id=$DISCORD_CHANNEL_ID name=project-$SLUG"
    # Persist channel id alongside project metadata so other agents can resolve it
    # without depending on the plugin's channel-project-map (which is set via
    # /clip connect-channel inside Discord and requires the gateway).
    if command -v python3 >/dev/null 2>&1; then
      python3 - <<EOF
import yaml
p = ".specpaper/project.yaml"
data = yaml.safe_load(open(p))
data.setdefault("project", {})["discord_channel_id"] = "$DISCORD_CHANNEL_ID"
with open(p, "w") as f:
    yaml.safe_dump(data, f, sort_keys=False)
EOF
    fi
  else
    echo "[bootstrap] Channel creation returned no id. Response:" >&2
    echo "$DISCORD_CREATE_RESPONSE" | jq -r '.message // .' >&2
  fi
else
  echo "[bootstrap] Discord channel creation skipped (DISCORD_BOT_TOKEN / DISCORD_GUILD_ID / DISCORD_PROJECTS_CATEGORY_ID not all set)."
  echo "[bootstrap] Manual fallback: create #project-$SLUG in Discord and run /clip connect-channel project:$SLUG"
fi

# 8. Register custom commands once per company (idempotent upsert).
# Also gated on Paperclip plugin runtime — skipped if the plugin isn't ready.
if [[ -x "$SCRIPT_DIR/discord-register-commands.sh" ]]; then
  bash "$SCRIPT_DIR/discord-register-commands.sh" 2>&1 | sed 's/^/[bootstrap.discord-cmds] /' || true
fi

# 9. Welcome post in the project channel
if [[ -n "$DISCORD_CHANNEL_ID" && -n "${DISCORD_BOT_TOKEN:-}" ]]; then
  WELCOME_BODY="$(jq -n \
    --arg content ":tada: **Project created: $NAME**

**Repo:** $REPO_URL
**Tracker:** $TRACKER_KIND ($TRACKER_ORG/$TRACKER_PROJECT)
**Customer tier:** $CUSTOMER_TIER → deployment_target: $DEPLOYMENT_TARGET

**Active agents:** ceo, cto, builder, builder-dotnet, builder-nextjs, devops, verifier, e2e-tester

Drive the lifecycle from this channel:
  \`!propose <idea>\` → \`!brainstorm <change>\` → \`!plan <change>\` → \`!build <change>\` → \`!verify <change>\` → \`!archive <change>\`
  \`!status\` for the dashboard." \
    '{content: $content}')"

  curl -sf -X POST \
    "https://discord.com/api/v10/channels/$DISCORD_CHANNEL_ID/messages" \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$WELCOME_BODY" >/dev/null 2>&1 \
    && echo "[bootstrap] Welcome message posted." \
    || echo "[bootstrap] Welcome message post failed (continuing)." >&2
fi

# 11. Hand off to CTO via a Paperclip child issue
curl -sf -X POST "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/issues" \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg projectId "$PROJECT_ID" \
    --arg title "Project bootstrapped — awaiting first feature request" \
    --arg description "Project $NAME ($SLUG) is set up. Discord channel: $DISCORD_CHANNEL_ID. Awaiting !propose from the user." \
    '{projectId: $projectId, title: $title, description: $description, assigneeAgentId: "cto", labels: ["specpaper", "bootstrap"]}')" >/dev/null

echo "[bootstrap] Done. Project: $NAME ($SLUG). projectId=$PROJECT_ID"
