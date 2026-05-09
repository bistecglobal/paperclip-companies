#!/usr/bin/env bash
# discord-sync.sh — Post chat-friendly artifact summaries to a project's
# Discord channel using Discord REST directly.
#
# Why direct REST instead of the plugin's discord_post tool: the plugin
# tool dispatcher requires a runContext that an agent driving Bash + curl
# cannot synthesize from inside its own run. Direct REST works as long as
# DISCORD_BOT_TOKEN is in the agent's env (which we do via the agent
# config's env block).
#
# Usage:
#   discord-sync.sh brainstorm-top5      <specpaper_dir> <change>
#   discord-sync.sh propose-summary      <specpaper_dir> <change>
#   discord-sync.sh plan-summary         <specpaper_dir> <change>
#   discord-sync.sh verify-verdict       <specpaper_dir> <change>
#   discord-sync.sh build-wave-status    <specpaper_dir> <change> <wave_no> <pending_count> <complete_count>
#   discord-sync.sh status-digest        <specpaper_dir>
#   discord-sync.sh principle-conflict   <specpaper_dir> <change> "<message>"
#   discord-sync.sh post                 <specpaper_dir> "<markdown>"
#
# Channel resolution order:
#   1. .specpaper/project.yaml -> project.discord_channel_id  (set by bootstrap)
#   2. Plugin's channel-project-map state via /clip connect-channel mapping (best effort)
#   3. DISCORD_DEFAULT_CHANNEL_ID env (last resort)
#
# Required env: DISCORD_BOT_TOKEN
# Optional env: DISCORD_DEFAULT_CHANNEL_ID, PAPERCLIP_API_URL, PAPERCLIP_API_KEY

set -euo pipefail

usage() { sed -n '2,28p' "$0" >&2; exit "${1:-0}"; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]] && usage

ACTION="$1"; shift

DISCORD_API="https://discord.com/api/v10"
PAPERCLIP_API_URL="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"

if [[ -z "${DISCORD_BOT_TOKEN:-}" ]]; then
  echo "[discord-sync] DISCORD_BOT_TOKEN not set; cannot post to Discord. Set it in the agent config env." >&2
  exit 0  # do not fail the parent action
fi

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

resolve_channel_id() {
  local sd="$1"
  local channel_id

  # 1. project.yaml
  if [[ -f "$sd/project.yaml" ]]; then
    channel_id="$(yaml_get "$sd/project.yaml" "project.discord_channel_id")"
    if [[ -n "$channel_id" ]]; then echo "$channel_id"; return; fi
  fi

  # 2. Plugin state (best-effort; will 404 on most local_trusted instances)
  local slug; slug="$(yaml_get "$sd/project.yaml" "project.slug")"
  if [[ -n "$slug" ]]; then
    channel_id="$(curl -sf "$PAPERCLIP_API_URL/api/plugins/paperclip-plugin-discord/state/channel-project-map" \
      -H "Authorization: Bearer ${PAPERCLIP_API_KEY:-local_trusted}" 2>/dev/null \
      | jq -r --arg slug "$slug" '.[$slug] // empty' 2>/dev/null || echo "")"
    if [[ -n "$channel_id" ]]; then echo "$channel_id"; return; fi
  fi

  # 3. fallback
  echo "${DISCORD_DEFAULT_CHANNEL_ID:-}"
}

post_to_channel() {
  local channel_id="$1" content="$2"
  if [[ -z "$channel_id" ]]; then
    echo "[discord-sync] No channel could be resolved — skipping post." >&2
    return 0
  fi
  # Discord caps message content at 2000 chars. We always reserve room for
  # the truncation suffix so the final body never exceeds the limit.
  local suffix=$'\n...(truncated; see full artifact in .specpaper/)'
  local budget=$((2000 - ${#suffix}))
  local trimmed
  if (( ${#content} > budget )); then
    trimmed="$(printf '%s' "$content" | head -c "$budget")$suffix"
  else
    trimmed="$content"
  fi
  curl -sf -X POST "$DISCORD_API/channels/$channel_id/messages" \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg c "$trimmed" '{content: $c}')" >/dev/null \
    && echo "[discord-sync] posted to channel $channel_id" \
    || echo "[discord-sync] post failed (non-fatal)" >&2
}

# Extract a section delimited by `## <name>` headers from a markdown file.
# Stops at the next `## ` header. Strips trailing blank lines.
extract_section() {
  local file="$1" header="$2"
  awk -v hdr="^## $header" '
    $0 ~ hdr { capturing=1; next }
    capturing && /^## / { capturing=0 }
    capturing { print }
  ' "$file" | sed -e '/./,$!d' | awk 'NF{lines=lines $0 RS} END {sub(/[\r\n]+$/,"",lines); print lines}'
}

case "$ACTION" in
  brainstorm-top5)
    SD="$1"; CHANGE="$2"
    BS="$SD/changes/$CHANGE/brainstorm.md"
    [[ -f "$BS" ]] || { echo "No brainstorm.md at $BS" >&2; exit 1; }
    CH="$(resolve_channel_id "$SD")"
    TECHNIQUE="$(grep -m1 -E '^\*\*Technique:\*\*' "$BS" | sed 's/\*\*Technique:\*\*[[:space:]]*//')"
    TOP5="$(extract_section "$BS" "Top 5 with rationale")"
    NEXT="$(extract_section "$BS" "Recommended next steps")"
    post_to_channel "$CH" ":bulb: **Brainstorm complete: \`$CHANGE\`** — _technique: ${TECHNIQUE}_

**Top 5 ideas:**
$TOP5

**Recommended next steps:**
$NEXT

_(Full session in \`.specpaper/changes/$CHANGE/brainstorm.md\`. Reply to push back, narrow down, or pick which to spec.)_"
    ;;

  propose-summary)
    SD="$1"; CHANGE="$2"
    PROPOSAL="$SD/changes/$CHANGE/proposal.md"
    [[ -f "$PROPOSAL" ]] || { echo "No proposal.md at $PROPOSAL" >&2; exit 1; }
    CH="$(resolve_channel_id "$SD")"
    PROBLEM="$(extract_section "$PROPOSAL" "Problem")"
    SOLUTION="$(extract_section "$PROPOSAL" "Proposed Solution")"
    SCOPE="$(extract_section "$PROPOSAL" "Scope")"
    DECISIONS="$(extract_section "$PROPOSAL" "Decisions to make")"
    [[ -z "$DECISIONS" ]] && DECISIONS="$(extract_section "$PROPOSAL" "Open questions")"
    post_to_channel "$CH" ":memo: **Proposal: \`$CHANGE\`**

**Problem:** $(printf '%s' "$PROBLEM" | head -c 400)

**Proposed solution:** $(printf '%s' "$SOLUTION" | head -c 600)

**Scope:** $(printf '%s' "$SCOPE" | head -c 300)

**Decisions for you:**
$(printf '%s' "$DECISIONS" | head -c 500)

_Reply with your decisions or adjustments. Or invoke \`/clip plan project:<name> change:$CHANGE\` once aligned._"
    ;;

  plan-summary)
    SD="$1"; CHANGE="$2"
    DESIGN="$SD/changes/$CHANGE/design.md"
    SPEC="$SD/changes/$CHANGE/spec.md"
    TASKS="$SD/changes/$CHANGE/tasks.md"
    [[ -f "$DESIGN" ]] || { echo "No design.md at $DESIGN" >&2; exit 1; }
    CH="$(resolve_channel_id "$SD")"
    APPROACH="$(extract_section "$DESIGN" "Technical Approach")"
    PRINCIPLES="$(extract_section "$DESIGN" "Principles applied")"
    AC="$(extract_section "$SPEC" "Acceptance Criteria")"
    TASK_COUNT=$(grep -cE "^- \[" "$TASKS" 2>/dev/null || echo 0)
    post_to_channel "$CH" ":compass: **Plan ready: \`$CHANGE\`** — _$TASK_COUNT tasks_

**Approach:** $(printf '%s' "$APPROACH" | head -c 400)

**Principles applied:**
$(printf '%s' "$PRINCIPLES" | head -c 500)

**Acceptance criteria (excerpt):**
$(printf '%s' "$AC" | head -c 400)

_Reply with adjustments, or invoke \`/clip build project:<name> change:$CHANGE\` to start the wave-based build._"
    ;;

  verify-verdict)
    SD="$1"; CHANGE="$2"
    VERIFY="$SD/changes/$CHANGE/verify-report.md"
    [[ -f "$VERIFY" ]] || { echo "No verify-report.md at $VERIFY" >&2; exit 1; }
    CH="$(resolve_channel_id "$SD")"
    VERDICT="$(grep -m1 -E '^\*\*Verdict:\*\*' "$VERIFY" | sed 's/\*\*Verdict:\*\*[[:space:]]*//')"
    SUMMARY="$(extract_section "$VERIFY" "Summary")"
    [[ -z "$SUMMARY" ]] && SUMMARY="$(head -c 600 "$VERIFY")"
    case "${VERDICT^^}" in
      *PASS*)    EMOJI=":white_check_mark:" ;;
      *PARTIAL*) EMOJI=":warning:" ;;
      *FAIL*)    EMOJI=":x:" ;;
      *)         EMOJI=":mag:" ;;
    esac
    post_to_channel "$CH" "$EMOJI **Verify: \`$CHANGE\`** — **$VERDICT**

$(printf '%s' "$SUMMARY" | head -c 1200)

_(Full report: \`.specpaper/changes/$CHANGE/verify-report.md\`)_"
    ;;

  build-wave-status)
    SD="$1"; CHANGE="$2"; WAVE="$3"; PENDING="$4"; COMPLETE="$5"
    CH="$(resolve_channel_id "$SD")"
    post_to_channel "$CH" ":construction: **Build wave $WAVE: \`$CHANGE\`** — $COMPLETE complete, $PENDING pending"
    ;;

  status-digest)
    SD="$1"
    CH="$(resolve_channel_id "$SD")"
    DIGEST="$(head -80 "$SD/STATUS.md" 2>/dev/null || echo '_(no STATUS.md yet)_')"
    post_to_channel "$CH" ":clipboard: **Project status**
\`\`\`
$DIGEST
\`\`\`"
    ;;

  principle-conflict)
    SD="$1"; CHANGE="$2"; MSG="$3"
    CH="$(resolve_channel_id "$SD")"
    post_to_channel "$CH" ":warning: **Principle conflict on \`$CHANGE\`** — CEO attention needed.

$MSG"
    ;;

  post)
    SD="$1"; MSG="$2"
    CH="$(resolve_channel_id "$SD")"
    post_to_channel "$CH" "$MSG"
    ;;

  *)
    usage 1
    ;;
esac
