#!/usr/bin/env bash
# Publishes the DMG built by scripts/release.sh as a GitHub Release (tag v<version>), with notes listing the
# commits since the previous release. Run it only when you want colleagues to get this version.
#
#   scripts/release.sh && scripts/publish.sh            # build, then publish
#   scripts/publish.sh --draft                          # create a draft release to review on GitHub first
#
# Download link for others: https://github.com/mduu/sylvra/releases/latest
set -euo pipefail
cd "$(dirname "$0")/.."

DRAFT=()
[[ "${1:-}" == "--draft" ]] && DRAFT=(--draft)

DMG=$(ls .build/release/Sylvra-*.dmg 2>/dev/null | head -1 || true)
[[ -n "$DMG" ]] || { echo "No DMG in .build/release — run scripts/release.sh first." >&2; exit 1; }
VERSION=$(basename "$DMG" .dmg | sed 's/^Sylvra-//')
TAG="v$VERSION"

# The DMG must be the build of the checked-out version (not one left over from an earlier build).
HEAD_VERSION=$(git show HEAD:Sylvra.xcodeproj/project.pbxproj | grep -m1 'MARKETING_VERSION = ' | sed -E 's/.*= ([^;]+);/\1/')
[[ "$VERSION" == "$HEAD_VERSION" ]] || {
  echo "$DMG is version $VERSION, but HEAD is $HEAD_VERSION — run scripts/release.sh first." >&2
  exit 1
}

xcrun stapler validate "$DMG" >/dev/null || { echo "$DMG is not notarized." >&2; exit 1; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "Commit your changes first." >&2; exit 1; }
git fetch --quiet --tags origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse '@{u}')" ]] || { echo "Push main first." >&2; exit 1; }
if gh release view "$TAG" >/dev/null 2>&1; then echo "Release $TAG exists already." >&2; exit 1; fi

PREVIOUS=$(git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null || true)
RANGE=${PREVIOUS:+$PREVIOUS..}HEAD
NOTES=$(mktemp)
trap 'rm -f "$NOTES"' EXIT
{
  echo "## Install"
  echo
  echo "Download **Sylvra-$VERSION.dmg**, open it and drag Sylvra into Applications."
  echo "Needs the [GitHub CLI](https://cli.github.com) (\`gh auth login\`); the AI features need [Claude Code](https://docs.claude.com/en/docs/claude-code)."
  echo
  if [[ -n "$PREVIOUS" ]]; then
    echo "## Changes since $PREVIOUS"
    echo
    git log --no-merges --format='- %s' "$RANGE" | grep -v -E '^- (Bump (version|build number)|README:)' || true
  else
    echo "First published release. See the [README](https://github.com/mduu/sylvra#readme) for what Sylvra does."
  fi
} > "$NOTES"

git tag -a "$TAG" -m "Sylvra $VERSION"
git push --quiet origin "$TAG"
gh release create "$TAG" "$DMG" --title "Sylvra $VERSION" --notes-file "$NOTES" ${DRAFT[@]+"${DRAFT[@]}"}
echo "✅ https://github.com/mduu/sylvra/releases/tag/$TAG"
