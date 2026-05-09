#!/usr/bin/env bash
# specpaper init — Initialize SpecPaper in a project directory
# Usage: init.sh <project_dir> [project_name] [project_description]

set -euo pipefail

PROJECT_DIR="${1:-.}"
PROJECT_NAME="${2:-$(basename "$(cd "$PROJECT_DIR" && pwd)")}"
PROJECT_DESC="${3:-}"

SPECPAPER_DIR="$PROJECT_DIR/.specpaper"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ -d "$SPECPAPER_DIR" ]; then
  echo "ERROR: .specpaper/ already exists in $PROJECT_DIR"
  exit 1
fi

# Create directory structure
mkdir -p "$SPECPAPER_DIR/changes/archive"

# Generate config from template
sed \
  -e "s|^  name: \"\"|  name: \"$PROJECT_NAME\"|" \
  -e "s|^  description: \"\"|  description: \"$PROJECT_DESC\"|" \
  "$SKILL_DIR/templates/config.yaml" > "$SPECPAPER_DIR/config.yaml"

# Create initial STATUS.md
cat > "$SPECPAPER_DIR/STATUS.md" << EOF
# 🦞 SpecPaper Dashboard

**Project:** $PROJECT_NAME
**Last Updated:** $(date -u +"%Y-%m-%d %H:%M UTC")

## Active Changes

_No active changes yet. Run \`specpaper propose "<idea>"\` to start._

## Pending Proposals

_None._

## Recently Completed

_None._

## Stats

- **Total changes:** 0
- **Active:** 0
- **Completed:** 0
EOF

echo "OK: Initialized SpecPaper in $SPECPAPER_DIR"
echo "  config: $SPECPAPER_DIR/config.yaml"
echo "  status: $SPECPAPER_DIR/STATUS.md"
echo "  changes: $SPECPAPER_DIR/changes/"
