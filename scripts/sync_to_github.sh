#!/bin/bash
# One-command Auto-Push script for Smart Navigation
# Usage: ./scripts/sync_to_github.sh ["Optional commit message"]

cd "$(dirname "$0")/.." || exit 1

# Check if there are any uncommitted changes
if [ -z "$(git status --porcelain)" ]; then
  echo "✨ No new changes to sync. Working tree is already clean."
  exit 0
fi

# Use custom message or auto-generate based on modified files
MSG="$1"
if [ -z "$MSG" ]; then
  CHANGED=$(git status --short | head -n 5 | awk '{print $2}' | paste -sd ", " -)
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
  MSG="Update ($TIMESTAMP): Modified $CHANGED"
fi

echo "📦 Staging changes..."
git add .

echo "📝 Creating commit: '$MSG'..."
git commit -m "$MSG"

# Note: The .git/hooks/post-commit hook will automatically run git push origin main!
echo "🎉 All changes are now live on GitHub!"
