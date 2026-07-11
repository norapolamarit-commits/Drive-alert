#!/usr/bin/env bash
# ============================================================
#  cleanup_for_github.sh
#  Finalises the GitHub-friendly folder structure for the doz repo.
#
#  WHAT IT DOES
#   1. Removes the OLD copies of files that were relocated:
#        DISTRIBUTION.md  ->  docs/DISTRIBUTION.md
#        build_apps.sh    ->  scripts/build_apps.sh
#   2. Stops tracking generated / local-only folders & files
#      (they stay on your disk, they just leave git):
#        outputs/  work/  smart_health_risk_alert_watch/
#        build/  .dart_tool/  *.iml  .DS_Store  .flutter-plugins-dependencies
#   3. Re-stages everything according to the new .gitignore.
#
#  Run it once from the repo root:
#       cd /Users/norapol/Documents/Doz
#       chmod +x cleanup_for_github.sh
#       ./cleanup_for_github.sh
#
#  Nothing is committed automatically — review with `git status`,
#  then commit and push yourself.
# ============================================================
set -e

cd "$(dirname "$0")"

if [ ! -d .git ]; then
  echo "❌ This is not a git repo root (no .git/). cd into the project first."
  exit 1
fi

echo "🧹 Cleaning up for GitHub..."

# 1) Delete OLD copies that now live in docs/ and scripts/ -----------
#    (only if the new copies exist, so we never lose the file)
if [ -f docs/DISTRIBUTION.md ] && [ -f DISTRIBUTION.md ]; then
  git rm -f --ignore-unmatch DISTRIBUTION.md >/dev/null 2>&1 || rm -f DISTRIBUTION.md
  echo "  • moved DISTRIBUTION.md  -> docs/"
fi
if [ -f scripts/build_apps.sh ] && [ -f build_apps.sh ]; then
  git rm -f --ignore-unmatch build_apps.sh >/dev/null 2>&1 || rm -f build_apps.sh
  echo "  • moved build_apps.sh    -> scripts/"
fi

# 2) Untrack generated / local-only paths (kept on disk) -------------
for p in outputs work smart_health_risk_alert_watch build .dart_tool \
         .DS_Store .flutter-plugins-dependencies vitaguard.iml; do
  if git ls-files --error-unmatch "$p" >/dev/null 2>&1; then
    git rm -r --cached --ignore-unmatch "$p" >/dev/null 2>&1 || true
    echo "  • untracked: $p"
  fi
done
# any other *.iml files
git ls-files '*.iml' 2>/dev/null | while read -r f; do
  git rm --cached --ignore-unmatch "$f" >/dev/null 2>&1 || true
  echo "  • untracked: $f"
done

# 3) Re-stage according to the new .gitignore ------------------------
git add -A

echo ""
echo "✅ Done. Review the result:"
echo "     git status"
echo "     git commit -m \"Reorganize project structure for GitHub\""
echo "     git push -u origin main"
