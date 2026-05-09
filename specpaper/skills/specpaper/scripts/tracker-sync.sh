#!/usr/bin/env bash
# tracker-sync.sh — Tracker abstraction over GitHub Issues and Azure DevOps Work Items.
# Replaces specclaw's gh-sync.sh. Dispatches on tracker.kind in .specpaper/config.yaml.
#
# Usage:
#   tracker-sync.sh setup
#   tracker-sync.sh create  <specpaper_dir> <change>
#   tracker-sync.sh update  <specpaper_dir> <change>
#   tracker-sync.sh comment <specpaper_dir> <change> "<message>"
#   tracker-sync.sh close   <specpaper_dir> <change>
#
# Tracker reference (issue number / work-item id) stored in:
#   <specpaper_dir>/changes/<change>/.tracker-ref
#
# Auth:
#   GitHub: GITHUB_TOKEN, or `gh auth login` (gh CLI preferred)
#   Azure DevOps: AZURE_DEVOPS_EXT_PAT, or `az login` (az CLI preferred)

set -euo pipefail

usage() { sed -n '2,18p' "$0" >&2; exit "${1:-0}"; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]] && usage

ACTION="$1"; shift

yaml_get() {
  local file="$1" path="$2"
  python3 -c "
import sys, yaml
with open('$file') as f: data = yaml.safe_load(f)
keys = '$path'.split('.')
cursor = data
for k in keys:
    if cursor is None: break
    cursor = cursor.get(k) if isinstance(cursor, dict) else None
print('' if cursor is None else cursor)
" 2>/dev/null || true
}

resolve_dir() { echo "$1/changes/$2"; }
read_tracker_kind() { yaml_get "$1/config.yaml" "tracker.kind"; }
read_tracker_ref()  { [[ -f "$1/.tracker-ref" ]] && cat "$1/.tracker-ref" || echo ""; }
write_tracker_ref() { echo "$2" > "$1/.tracker-ref"; }

build_body() {
  local change_dir="$1" body=""
  [[ -f "$change_dir/proposal.md" ]] && body+=$(cat "$change_dir/proposal.md")$'\n\n'
  if [[ -f "$change_dir/tasks.md" ]]; then
    body+=$'## Tasks\n\n'
    body+=$(grep -E "^- \[" "$change_dir/tasks.md" || true)
  fi
  echo "$body"
}

# ---------- GitHub ----------
gh_setup() {
  if command -v gh >/dev/null 2>&1; then
    gh auth status >&2 || { echo "gh auth login required" >&2; return 1; }
  elif [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "Either gh CLI or GITHUB_TOKEN required" >&2; return 1
  fi
}

gh_create() {
  local sd="$1" change="$2" change_dir
  change_dir="$(resolve_dir "$sd" "$change")"
  local title="[specpaper] $change"
  local body; body="$(build_body "$change_dir")"
  local label; label="$(yaml_get "$sd/config.yaml" "tracker.github.label")"; label="${label:-specpaper}"

  local num
  if command -v gh >/dev/null 2>&1; then
    num="$(gh issue create --title "$title" --body "$body" --label "$label" 2>/dev/null | grep -oE '[0-9]+$' || true)"
  else
    local repo; repo="$(yaml_get "$sd/config.yaml" "tracker.github.repo")"
    num="$(curl -sf -X POST "https://api.github.com/repos/$repo/issues" \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -d "$(jq -n --arg t "$title" --arg b "$body" --arg l "$label" '{title:$t,body:$b,labels:[$l]}')" \
      | jq -r '.number')"
  fi
  [[ -z "$num" ]] && { echo "GitHub create failed" >&2; return 1; }
  write_tracker_ref "$change_dir" "$num"
  echo "$num"
}

gh_update() {
  local sd="$1" change="$2" change_dir num body
  change_dir="$(resolve_dir "$sd" "$change")"
  num="$(read_tracker_ref "$change_dir")"
  [[ -z "$num" ]] && { echo "No tracker ref; run create first" >&2; return 1; }
  body="$(build_body "$change_dir")"
  if command -v gh >/dev/null 2>&1; then
    gh issue edit "$num" --body "$body" >/dev/null
  else
    local repo; repo="$(yaml_get "$sd/config.yaml" "tracker.github.repo")"
    curl -sf -X PATCH "https://api.github.com/repos/$repo/issues/$num" \
      -H "Authorization: token $GITHUB_TOKEN" \
      -d "$(jq -n --arg b "$body" '{body:$b}')" >/dev/null
  fi
}

gh_comment() {
  local sd="$1" change="$2" message="$3" change_dir num
  change_dir="$(resolve_dir "$sd" "$change")"
  num="$(read_tracker_ref "$change_dir")"
  [[ -z "$num" ]] && return 0
  if command -v gh >/dev/null 2>&1; then
    gh issue comment "$num" --body "$message" >/dev/null
  else
    local repo; repo="$(yaml_get "$sd/config.yaml" "tracker.github.repo")"
    curl -sf -X POST "https://api.github.com/repos/$repo/issues/$num/comments" \
      -H "Authorization: token $GITHUB_TOKEN" \
      -d "$(jq -n --arg b "$message" '{body:$b}')" >/dev/null
  fi
}

gh_close() {
  local sd="$1" change="$2" change_dir num
  change_dir="$(resolve_dir "$sd" "$change")"
  num="$(read_tracker_ref "$change_dir")"
  [[ -z "$num" ]] && return 0
  if command -v gh >/dev/null 2>&1; then
    gh issue close "$num" >/dev/null
  else
    local repo; repo="$(yaml_get "$sd/config.yaml" "tracker.github.repo")"
    curl -sf -X PATCH "https://api.github.com/repos/$repo/issues/$num" \
      -H "Authorization: token $GITHUB_TOKEN" \
      -d '{"state":"closed"}' >/dev/null
  fi
}

# ---------- Azure DevOps ----------
az_setup() {
  if command -v az >/dev/null 2>&1; then
    az account show >/dev/null 2>&1 || echo "az login recommended (or set AZURE_DEVOPS_EXT_PAT)" >&2
  elif [[ -z "${AZURE_DEVOPS_EXT_PAT:-}" ]]; then
    echo "Either az CLI or AZURE_DEVOPS_EXT_PAT required" >&2; return 1
  fi
}

az_org_project() {
  local sd="$1"
  local org; org="$(yaml_get "$sd/config.yaml" "tracker.azure_devops.organization")"
  local proj; proj="$(yaml_get "$sd/config.yaml" "tracker.azure_devops.project")"
  echo "$org|$proj"
}

az_create() {
  local sd="$1" change="$2" change_dir title body wit
  change_dir="$(resolve_dir "$sd" "$change")"
  IFS='|' read -r org proj <<<"$(az_org_project "$sd")"
  wit="$(yaml_get "$sd/config.yaml" "tracker.azure_devops.work_item_type")"; wit="${wit:-User Story}"
  title="[specpaper] $change"
  body="$(build_body "$change_dir")"
  local id
  if command -v az >/dev/null 2>&1; then
    id="$(az boards work-item create --org "$org" --project "$proj" --type "$wit" \
      --title "$title" --description "$body" --query id -o tsv 2>/dev/null || true)"
  else
    id="$(curl -sfu ":$AZURE_DEVOPS_EXT_PAT" \
      -X POST "$org/$proj/_apis/wit/workitems/\$$wit?api-version=7.1" \
      -H "Content-Type: application/json-patch+json" \
      -d "$(jq -n --arg t "$title" --arg b "$body" \
        '[{op:"add",path:"/fields/System.Title",value:$t},{op:"add",path:"/fields/System.Description",value:$b}]')" \
      | jq -r '.id')"
  fi
  [[ -z "$id" || "$id" == "null" ]] && { echo "AzDo create failed" >&2; return 1; }
  write_tracker_ref "$change_dir" "$id"
  echo "$id"
}

az_update() {
  local sd="$1" change="$2" change_dir id body
  change_dir="$(resolve_dir "$sd" "$change")"
  id="$(read_tracker_ref "$change_dir")"
  [[ -z "$id" ]] && return 0
  IFS='|' read -r org proj <<<"$(az_org_project "$sd")"
  body="$(build_body "$change_dir")"
  if command -v az >/dev/null 2>&1; then
    az boards work-item update --org "$org" --id "$id" --description "$body" >/dev/null 2>&1 || true
  else
    curl -sfu ":$AZURE_DEVOPS_EXT_PAT" \
      -X PATCH "$org/_apis/wit/workitems/$id?api-version=7.1" \
      -H "Content-Type: application/json-patch+json" \
      -d "$(jq -n --arg b "$body" '[{op:"add",path:"/fields/System.Description",value:$b}]')" >/dev/null
  fi
}

az_comment() {
  local sd="$1" change="$2" message="$3" change_dir id
  change_dir="$(resolve_dir "$sd" "$change")"
  id="$(read_tracker_ref "$change_dir")"
  [[ -z "$id" ]] && return 0
  IFS='|' read -r org proj <<<"$(az_org_project "$sd")"
  if command -v az >/dev/null 2>&1; then
    az boards work-item update --org "$org" --id "$id" --discussion "$message" >/dev/null 2>&1 || true
  else
    curl -sfu ":$AZURE_DEVOPS_EXT_PAT" \
      -X POST "$org/$proj/_apis/wit/workItems/$id/comments?api-version=7.1-preview.3" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg t "$message" '{text:$t}')" >/dev/null
  fi
}

az_close() {
  local sd="$1" change="$2" change_dir id
  change_dir="$(resolve_dir "$sd" "$change")"
  id="$(read_tracker_ref "$change_dir")"
  [[ -z "$id" ]] && return 0
  IFS='|' read -r org proj <<<"$(az_org_project "$sd")"
  if command -v az >/dev/null 2>&1; then
    az boards work-item update --org "$org" --id "$id" --state "Done" >/dev/null 2>&1 || true
  else
    curl -sfu ":$AZURE_DEVOPS_EXT_PAT" \
      -X PATCH "$org/_apis/wit/workitems/$id?api-version=7.1" \
      -H "Content-Type: application/json-patch+json" \
      -d '[{"op":"add","path":"/fields/System.State","value":"Done"}]' >/dev/null
  fi
}

# ---------- Dispatcher ----------
case "$ACTION" in
  setup)
    SD="${1:-.specpaper}"
    [[ -d "$SD" ]] || { echo "specpaper dir not found: $SD" >&2; exit 1; }
    KIND="$(read_tracker_kind "$SD")"
    case "$KIND" in
      github) gh_setup ;;
      azure-devops) az_setup ;;
      none) echo "tracker: none — no setup needed" ;;
      *) echo "Unknown tracker.kind: $KIND" >&2; exit 1 ;;
    esac
    ;;
  create|update|comment|close)
    SD="$1"; CHANGE="$2"; shift 2
    KIND="$(read_tracker_kind "$SD")"
    case "$KIND" in
      github) "gh_$ACTION" "$SD" "$CHANGE" "$@" ;;
      azure-devops) "az_$ACTION" "$SD" "$CHANGE" "$@" ;;
      none) : ;;
      *) echo "Unknown tracker.kind: $KIND" >&2; exit 1 ;;
    esac
    ;;
  *)
    usage 1
    ;;
esac
