#!/usr/bin/env bash
# Installs the git pre-push hook. Safe to re-run: it updates the hook in place.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Run this from inside the lab repo (no git repository found)." >&2
  exit 1
}
cd "$ROOT"

SRC="hooks/pre-push"
[ -f "$SRC" ] || { echo "$SRC not found. Is this the lab repo?" >&2; exit 1; }

# If a hook manager (husky, lefthook) moved the hooks folder, a hook copied into
# .git/hooks would never run. Say so instead of installing something inert.
CUSTOM=$(git config --get core.hooksPath || true)
if [ -n "$CUSTOM" ]; then
  echo "core.hooksPath is set to '$CUSTOM', so git ignores .git/hooks." >&2
  echo "Call $ROOT/$SRC from your hook manager's pre-push step instead." >&2
  exit 1
fi

DEST="$(git rev-parse --git-dir)/hooks/pre-push"
mkdir -p "$(dirname "$DEST")"

# Never overwrite someone else's hook without keeping a copy.
if [ -e "$DEST" ] && ! cmp -s "$SRC" "$DEST"; then
  BACKUP="$DEST.bak.$(date +%Y%m%d%H%M%S)"
  mv "$DEST" "$BACKUP"
  echo "Existing pre-push hook saved to $BACKUP"
fi

cp "$SRC" "$DEST"
chmod +x "$DEST"

echo "✅ Pre-push hook installed"
echo "   Every git push now audits the commits being pushed."
echo "   Skip it once, knowingly:  git push --no-verify"

if ! command -v agy &> /dev/null; then
  echo ""
  echo "⚠️  agy is not installed, so pushes will be blocked until you install it:"
  echo "   curl -fsSL https://antigravity.google/cli/install.sh | bash"
fi
