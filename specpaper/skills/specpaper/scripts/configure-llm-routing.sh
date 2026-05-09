#!/usr/bin/env bash
# configure-llm-routing.sh — Opt agents into a non-default LLM provider after import.
#
# The SpecPaper company defaults all agents to Anthropic direct (per COMPANY.md
# `defaults.llm`). This script lets you opt specific agents into the Minimax
# (Anthropic-compatible) endpoint for cost savings — but only after verifying
# that the required secret is configured.
#
# Why opt-in? If the company package hardcoded `llm_override: minimax` on builder
# agents, importing the company without first creating the `minimax_api_key`
# secret would leave those agents broken at runtime (no auth → CLI fails).
# Opt-in keeps the import deterministic and surfaces the dependency clearly.
#
# Usage:
#   configure-llm-routing.sh enable-minimax  <agent-name>           # one agent
#   configure-llm-routing.sh enable-minimax  --all-builders          # builder + builder-dotnet + builder-nextjs
#   configure-llm-routing.sh disable-minimax <agent-name>            # revert one agent
#   configure-llm-routing.sh disable-minimax --all-builders
#   configure-llm-routing.sh status                                  # show current routing per agent
#
# Requires: PAPERCLIP_API_KEY, PAPERCLIP_API_URL, PAPERCLIP_COMPANY_ID

set -euo pipefail

PAPERCLIP_API_URL="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"
COMPANY="${PAPERCLIP_COMPANY_ID:?PAPERCLIP_COMPANY_ID required}"

usage() { sed -n '2,22p' "$0" >&2; exit "${1:-0}"; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]] && usage

ACTION="$1"; shift

api_get() {
  curl -sf "$PAPERCLIP_API_URL$1" -H "Authorization: Bearer $PAPERCLIP_API_KEY"
}

api_patch() {
  local path="$1" body="$2"
  curl -sf -X PATCH "$PAPERCLIP_API_URL$path" \
    -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$body"
}

# Resolve agent id from name within the SpecPaper company
resolve_agent_id() {
  local name="$1"
  api_get "/api/companies/$COMPANY/agents" \
    | jq -r --arg n "$name" '.items[] | select(.name == $n or .slug == $n) | .id' \
    | head -1
}

# Verify a Paperclip secret exists (returns "yes" / "no" — does not leak the value)
secret_exists() {
  local name="$1"
  api_get "/api/secrets?name=$name" 2>/dev/null \
    | jq -r --arg n "$name" '
        if (.items // []) | map(.name) | index($n) then "yes" else "no" end
      ' 2>/dev/null || echo "no"
}

resolve_targets() {
  local arg="$1"
  if [[ "$arg" == "--all-builders" ]]; then
    echo "builder builder-dotnet builder-nextjs"
  else
    echo "$arg"
  fi
}

apply_minimax_to_agent() {
  local agent_name="$1"
  local agent_id; agent_id="$(resolve_agent_id "$agent_name")"
  if [[ -z "$agent_id" ]]; then
    echo "[configure] ERROR: agent '$agent_name' not found in company $COMPANY" >&2
    return 1
  fi

  local body
  body="$(jq -n '
    {
      config: {
        model: "claude-haiku-4-5",
        env: {
          ANTHROPIC_BASE_URL: "https://api.minimax.io/anthropic",
          ANTHROPIC_API_KEY: "${secret:minimax_api_key}"
        }
      }
    }')"

  api_patch "/api/companies/$COMPANY/agents/$agent_id" "$body" >/dev/null
  echo "[configure] $agent_name → minimax"
}

revert_to_default() {
  local agent_name="$1"
  local agent_id; agent_id="$(resolve_agent_id "$agent_name")"
  if [[ -z "$agent_id" ]]; then
    echo "[configure] ERROR: agent '$agent_name' not found" >&2
    return 1
  fi

  # Clear the override env + model. Paperclip falls back to defaults.llm from COMPANY.md.
  local body='{"config": {"model": null, "env": {"ANTHROPIC_BASE_URL": null, "ANTHROPIC_API_KEY": null}}}'
  api_patch "/api/companies/$COMPANY/agents/$agent_id" "$body" >/dev/null
  echo "[configure] $agent_name → anthropic direct (defaults)"
}

show_status() {
  echo "[configure] LLM routing status for company $COMPANY:"
  api_get "/api/companies/$COMPANY/agents" \
    | jq -r '.items[] | [
        .name,
        (.config.env.ANTHROPIC_BASE_URL // "anthropic-direct"),
        (.config.model // "(default)")
      ] | @tsv' \
    | column -t -s $'\t'
}

case "$ACTION" in
  enable-minimax)
    [[ $# -eq 0 ]] && usage 1
    SECRET_OK="$(secret_exists "minimax_api_key")"
    if [[ "$SECRET_OK" != "yes" ]]; then
      cat >&2 <<EOF
[configure] ERROR: Paperclip secret 'minimax_api_key' is not configured.
Create it first:
  Paperclip Settings → Secrets → New secret → name: minimax_api_key
Or via API:
  curl -X POST $PAPERCLIP_API_URL/api/secrets \\
    -H "Authorization: Bearer \$PAPERCLIP_API_KEY" \\
    -H "Content-Type: application/json" \\
    -d '{"name":"minimax_api_key","value":"<your-minimax-key>"}'
Then re-run this command.
EOF
      exit 1
    fi
    for target in $(resolve_targets "$1"); do
      apply_minimax_to_agent "$target"
    done
    echo "[configure] Done. Run 'configure-llm-routing.sh status' to verify."
    ;;
  disable-minimax)
    [[ $# -eq 0 ]] && usage 1
    for target in $(resolve_targets "$1"); do
      revert_to_default "$target"
    done
    echo "[configure] Done. Run 'configure-llm-routing.sh status' to verify."
    ;;
  status)
    show_status
    ;;
  *)
    usage 1
    ;;
esac
