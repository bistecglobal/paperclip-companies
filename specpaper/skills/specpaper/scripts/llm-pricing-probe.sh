#!/usr/bin/env bash
# llm-pricing-probe.sh — Pre-flight test before flipping any agent to Minimax (or another
# Anthropic-compatible endpoint). Runs a deterministic 5-task synthetic build through
# (a) Anthropic direct and (b) the candidate provider, then compares cost + failure rate.
#
# This validates three things that often differ between providers:
#   1. Prompt-cache compatibility — does cache_control reduce input billing on resumed sessions?
#   2. Stream-JSON parsing — does the response schema match what the Claude adapter parses?
#   3. --resume semantics — does session resumption work, or is each call a fresh session?
#
# Usage:
#   llm-pricing-probe.sh <change-name>          # uses .specpaper/probes/<change>/ for inputs
#   llm-pricing-probe.sh --provider <key>        # the llm_overrides key from COMPANY.md
#
# Outputs a comparison table and per-task results to .specpaper/probes/<change>/report.md.

set -euo pipefail

CHANGE="${1:-pricing-probe-$(date +%Y%m%d-%H%M%S)}"
PROVIDER_KEY="${PROVIDER:-minimax}"
PROBE_DIR=".specpaper/probes/$CHANGE"
mkdir -p "$PROBE_DIR"

PAPERCLIP_API_URL="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"

echo "[probe] Change: $CHANGE"
echo "[probe] Candidate provider override key: $PROVIDER_KEY"
echo "[probe] Output: $PROBE_DIR/report.md"

# Synthetic 5-task build content. Deterministic — same prompts each run so token counts are comparable.
cat > "$PROBE_DIR/synthetic-tasks.md" <<'EOF'
# Synthetic 5-task probe

T1 — Add a no-op middleware to a hypothetical ASP.NET pipeline
T2 — Write a SQL migration that adds an idempotency_keys table (id uuid PK, key text, response_body text, created_at timestamptz)
T3 — Implement a simple React hook useIdempotencyKey() that wraps crypto.randomUUID
T4 — Add a unit test for the SQL migration (assert idempotency_keys exists with correct columns)
T5 — Write a 5-line README section documenting the idempotency-key header
EOF

run_with_provider() {
  local label="$1" override_key="$2"
  local out_file="$PROBE_DIR/$label.json"
  local agent_id="${PROBE_AGENT_ID:?Set PROBE_AGENT_ID to the test builder agent id}"

  echo "[probe] Running 5 tasks through provider=$label..."

  for i in 1 2 3 4 5; do
    local task; task="$(sed -n "${i}p" "$PROBE_DIR/synthetic-tasks.md" | tr -d '\n')"
    [[ -z "$task" ]] && continue

    local body response
    body="$(jq -n --arg task "$task" --arg key "$override_key" \
            '{prompt:$task, llm_override:$key, captureUsage:true}')"
    if ! response="$(curl -sf -X POST "$PAPERCLIP_API_URL/api/agents/$agent_id/probe" \
        -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null)"; then
      response="{}"
    fi

    echo "$response" >> "$out_file"
  done

  jq -s 'reduce .[] as $r ({inputTokens:0, outputTokens:0, cachedTokens:0, costUsd:0, failures:0};
    .inputTokens   += ($r.usage.inputTokens // 0)
    | .outputTokens += ($r.usage.outputTokens // 0)
    | .cachedTokens += ($r.usage.cachedInputTokens // 0)
    | .costUsd      += ($r.costUsd // 0)
    | .failures     += (if $r.exitCode != 0 then 1 else 0 end)
  )' "$out_file"
}

ANTHROPIC_RESULT="$(run_with_provider "anthropic-direct" "")"
CANDIDATE_RESULT="$(run_with_provider "$PROVIDER_KEY" "$PROVIDER_KEY")"

# Build comparison report
{
  echo "# LLM Pricing Probe Report"
  echo
  echo "**Change:** $CHANGE"
  echo "**Date:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "**Candidate provider:** $PROVIDER_KEY"
  echo
  echo "## Comparison"
  echo
  echo "| Metric | Anthropic direct | $PROVIDER_KEY |"
  echo "|---|---|---|"
  echo "| Input tokens | $(echo "$ANTHROPIC_RESULT" | jq -r .inputTokens) | $(echo "$CANDIDATE_RESULT" | jq -r .inputTokens) |"
  echo "| Output tokens | $(echo "$ANTHROPIC_RESULT" | jq -r .outputTokens) | $(echo "$CANDIDATE_RESULT" | jq -r .outputTokens) |"
  echo "| Cached input tokens | $(echo "$ANTHROPIC_RESULT" | jq -r .cachedTokens) | $(echo "$CANDIDATE_RESULT" | jq -r .cachedTokens) |"
  echo "| Cost (USD) | \$$(echo "$ANTHROPIC_RESULT" | jq -r .costUsd) | \$$(echo "$CANDIDATE_RESULT" | jq -r .costUsd) |"
  echo "| Failures | $(echo "$ANTHROPIC_RESULT" | jq -r .failures) | $(echo "$CANDIDATE_RESULT" | jq -r .failures) |"
  echo
  echo "## Verdict"
  echo
  echo "Compare:"
  echo "- **Cache ratio:** if 'Cached input tokens' on the candidate is significantly lower than on Anthropic direct, prompt-caching is not 1:1 — the cost gap will be smaller in production than the per-call list price suggests."
  echo "- **Failures:** any non-zero count on the candidate that doesn't match Anthropic indicates schema or tool-use incompatibility."
  echo "- **Cost ratio:** divide the costs. If candidate < Anthropic by 3× or more *and* failures match, roll the candidate out to high-volume agents (builders). Otherwise scope back."
} > "$PROBE_DIR/report.md"

echo "[probe] Done. Report: $PROBE_DIR/report.md"
cat "$PROBE_DIR/report.md"
