#!/usr/bin/env bash
# discord-register-commands.sh — Register !propose, !plan, !build, !verify, !archive,
# !status, !brainstorm, !principle-override custom commands with the Discord plugin.
#
# Idempotent — the plugin upserts on duplicate command names. Run once per company on
# bootstrap or after upgrading the plugin.
#
# Requires: PAPERCLIP_API_KEY, PAPERCLIP_API_URL, PAPERCLIP_COMPANY_ID

set -euo pipefail

PAPERCLIP_API_URL="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"
COMPANY="${PAPERCLIP_COMPANY_ID:?PAPERCLIP_COMPANY_ID required}"

register() {
  local name="$1" description="$2" agent="$3" params="$4"
  curl -sf -X POST "$PAPERCLIP_API_URL/api/plugins/paperclip-plugin-discord/tools/register_custom_command/invoke" \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg companyId "$COMPANY" \
      --arg cmd "$name" \
      --arg desc "$description" \
      --arg agent "$agent" \
      --argjson params "$params" \
      '{companyId:$companyId, command:$cmd, description:$desc, routeToAgent:$agent, parameters:$params}')" >/dev/null
  echo "[register] !$name → $agent"
}

register propose \
  "Create a new change proposal" \
  cto \
  '[{"name":"idea","description":"One-line description of the feature/fix","required":true}]'

register brainstorm \
  "Run a brainstorm session for a change (optional, before plan)" \
  cto \
  '[{"name":"change","description":"Change slug","required":true},{"name":"technique","description":"Optional: brain-methods technique name","required":false}]'

register plan \
  "Generate spec.md, design.md, tasks.md for a change" \
  cto \
  '[{"name":"change","description":"Change slug","required":true}]'

register build \
  "Start the wave-based build for a change" \
  cto \
  '[{"name":"change","description":"Change slug","required":true}]'

register verify \
  "Run the static + dynamic audits for a change" \
  cto \
  '[{"name":"change","description":"Change slug","required":true}]'

register archive \
  "Archive a completed change" \
  cto \
  '[{"name":"change","description":"Change slug","required":true}]'

register status \
  "Post the project status dashboard" \
  cto \
  '[{"name":"change","description":"Optional change slug for per-change status","required":false}]'

register principle-override \
  "Override a principle for the current change (CEO only)" \
  ceo \
  '[{"name":"principle","description":"Principle id","required":true},{"name":"rationale","description":"Why we are overriding","required":true}]'

echo "[register] Done."
