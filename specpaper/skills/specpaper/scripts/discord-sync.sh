#!/usr/bin/env bash
# discord-sync.sh — SpecPaper-specific Discord posts that aren't covered by the plugin's
# auto-emitted issue-lifecycle events.
#
# Most events (issue-created, issue-done, approval-created, agent-error) are auto-posted by
# bistecglobal/paperclip-plugin-discord. This helper covers only the gaps:
#   - brainstorm-complete summary
#   - status-dashboard digest (on demand)
#   - principle-conflict announcements
#
# Usage:
#   discord-sync.sh brainstorm-summary <specpaper_dir> <change>
#   discord-sync.sh status-digest      <specpaper_dir>
#   discord-sync.sh principle-conflict <specpaper_dir> <change> "<message>"
#
# Requires: PAPERCLIP_API_KEY, PAPERCLIP_API_URL, PAPERCLIP_COMPANY_ID

set -euo pipefail

usage() { sed -n '2,15p' "$0" >&2; exit "${1:-0}"; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]] && usage

ACTION="$1"; shift
PAPERCLIP_API_URL="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"

yaml_get() {
  python3 -c "
import yaml
with open('$1') as f: data = yaml.safe_load(f)
keys = '$2'.split('.')
cursor = data
for k in keys:
    if cursor is None: break
    cursor = cursor.get(k) if isinstance(cursor, dict) else None
print('' if cursor is None else cursor)
" 2>/dev/null || true
}

# Resolve the project's Discord channel id by asking the plugin (uses channel-project-map state)
resolve_channel_id() {
  local sd="$1"
  local slug; slug="$(yaml_get "$sd/project.yaml" "project.slug")"
  curl -sf "$PAPERCLIP_API_URL/api/plugins/paperclip-plugin-discord/state/channel-project-map" \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" 2>/dev/null \
    | jq -r --arg slug "$slug" '.[$slug] // empty' || echo ""
}

post_to_channel() {
  local channel_id="$1" content="$2"
  [[ -z "$channel_id" ]] && { echo "[discord-sync] No channel mapped — skipping post" >&2; return 0; }
  curl -sf -X POST "$PAPERCLIP_API_URL/api/plugins/paperclip-plugin-discord/tools/discord_post/invoke" \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg ch "$channel_id" --arg c "$content" '{channelId:$ch, content:$c}')" >/dev/null
}

case "$ACTION" in
  brainstorm-summary)
    SD="$1"; CHANGE="$2"
    BS="$SD/changes/$CHANGE/brainstorm.md"
    [[ -f "$BS" ]] || { echo "No brainstorm.md found" >&2; exit 1; }
    CH="$(resolve_channel_id "$SD")"
    # Extract Top 5 section
    TOP5="$(awk '/^## Top 5 with rationale/,/^## /' "$BS" | sed '$d')"
    post_to_channel "$CH" ":bulb: **Brainstorm complete: $CHANGE**

$TOP5

Full session: \`.specpaper/changes/$CHANGE/brainstorm.md\` (mirrored to docs/)"
    ;;
  status-digest)
    SD="$1"
    CH="$(resolve_channel_id "$SD")"
    DIGEST="$(head -60 "$SD/STATUS.md" 2>/dev/null || echo '_(no STATUS.md yet)_')"
    post_to_channel "$CH" ":clipboard: **Project status digest**

\`\`\`
$DIGEST
\`\`\`"
    ;;
  principle-conflict)
    SD="$1"; CHANGE="$2"; MSG="$3"
    CH="$(resolve_channel_id "$SD")"
    post_to_channel "$CH" ":warning: **Principle conflict on $CHANGE** — CEO attention needed.

$MSG"
    ;;
  *)
    usage 1
    ;;
esac
