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
#   PAPERCLIP_API_KEY        — already set by the Paperclip Claude adapter
#   PAPERCLIP_API_URL        — e.g. http://127.0.0.1:3100
#   PAPERCLIP_COMPANY_ID     — UUID of the SpecPaper company (set per-instance)
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
if [[ ! -d ".specpaper" ]]; then
  bash "$SCRIPT_DIR/init.sh" .specpaper
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

# 5. Update config.yaml with tracker info
sed -i.bak \
  -e "s|kind: \"none\"|kind: \"$TRACKER_KIND\"|" \
  -e "s|repo: \"\"|repo: \"$TRACKER_ORG/$TRACKER_PROJECT\"|" \
  -e "s|organization: \"\"|organization: \"$TRACKER_ORG\"|" \
  -e "s|project: \"\"|project: \"$TRACKER_PROJECT\"|" \
  .specpaper/config.yaml || true
rm -f .specpaper/config.yaml.bak

# 6. Add gitignore entries
GITIGNORE=".gitignore"
touch "$GITIGNORE"
for entry in ".specpaper/changes/*/e2e-evidence/" ".specpaper/changes/*/.task-context-*" ".specpaper/worktrees/" ".specpaper/changes/archive/"; do
  grep -qxF "$entry" "$GITIGNORE" || echo "$entry" >> "$GITIGNORE"
done

# 7. Discord: create channel via the forked plugin create_channel tool
echo "[bootstrap] Creating Discord channel via plugin..."
DISCORD_CREATE_RESPONSE="$(
  curl -sf -X POST "$PAPERCLIP_API_URL/api/plugins/paperclip-plugin-discord/tools/create_channel/invoke" \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg companyId "$PAPERCLIP_COMPANY_ID" \
      --arg name "project-$SLUG" \
      --arg topic "$NAME — managed by SpecPaper. Use !propose, !plan, !build, !verify, !archive, !status." \
      '{companyId: $companyId, name: $name, topic: $topic, useCategoryFromConfig: true}')" 2>&1 || echo '{}'
)"
DISCORD_CHANNEL_ID="$(echo "$DISCORD_CREATE_RESPONSE" | jq -r '.channelId // empty')"

if [[ -n "$DISCORD_CHANNEL_ID" ]]; then
  # 8. Connect channel to project (per-project routing in plugin state)
  curl -sf -X POST "$PAPERCLIP_API_URL/api/plugins/paperclip-plugin-discord/tools/connect_channel/invoke" \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg companyId "$PAPERCLIP_COMPANY_ID" \
      --arg channelId "$DISCORD_CHANNEL_ID" \
      --arg projectSlug "$SLUG" \
      '{companyId: $companyId, channelId: $channelId, projectSlug: $projectSlug}')" >/dev/null || true
  echo "[bootstrap] Connected channel $DISCORD_CHANNEL_ID → project $SLUG"
else
  echo "[bootstrap] Channel creation failed or plugin unavailable. Skipping channel wiring."
  echo "[bootstrap] Manual fallback: create #project-$SLUG and run /clip connect-channel project:$SLUG"
fi

# 9. Register custom commands once per company
bash "$SCRIPT_DIR/discord-register-commands.sh"

# 10. Welcome post
if [[ -n "$DISCORD_CHANNEL_ID" ]]; then
  curl -sf -X POST "$PAPERCLIP_API_URL/api/plugins/paperclip-plugin-discord/tools/discord_post/invoke" \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg channelId "$DISCORD_CHANNEL_ID" \
      --arg content ":tada: **Project created: $NAME**

Repo: $REPO_URL
Tracker: $TRACKER_KIND ($TRACKER_ORG/$TRACKER_PROJECT)
Customer tier: **$CUSTOMER_TIER** → deployment_target: **$DEPLOYMENT_TARGET**

**Active agents:** ceo, cto, builder, builder-dotnet, builder-nextjs, devops, verifier, e2e-tester

Drive the lifecycle from this channel:
  \`!propose <idea>\` → \`!brainstorm <change>\` → \`!plan <change>\` → \`!build <change>\` → \`!verify <change>\` → \`!archive <change>\`
  \`!status\` for the dashboard." \
      '{channelId: $channelId, content: $content}')" >/dev/null || true
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
