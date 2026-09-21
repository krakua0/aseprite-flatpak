#!/usr/bin/env bash
# bump.sh — resolve latest aseprite/skia/runtime versions, then delegate
# file edits to bump_edit.py (all regexps live there)
#
# Usage:
#   ./bump.sh                # bump to latest aseprite release + matching skia + latest flathub runtime
#   ./bump.sh --check        # print resolved values, edit nothing (dry-run)
#   ./bump.sh v1.3.18.1      # pin to a specific aseprite tag
#   ./bump.sh --skia-only    # re-fetch skia asset for currently-pinned aseprite tag only
#
# Requires: curl jq sha256sum sed grep python3 flatpak
# Reads INSTALL.md of the target aseprite tag to discover the required skia branch
# (e.g. aseprite-m124), then finds the matching skia release tag (m124-<sha>).

set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")" # run from repo dir regardless of caller cwd

MANIFEST="aseprite.yaml"
ASE_REPO="aseprite/aseprite"
SKIA_REPO="aseprite/skia"
RUNTIME="org.freedesktop.Platform"
RUNTIME_FALLBACK="25.08"
SKIA_ASSET="Skia-Linux-Release-x64.zip"

die() {
	echo "ERROR: $*" >&2
	exit 1
}
need() { command -v "$1" >/dev/null 2>&1 || die "missing dep: $1"; }
for d in curl jq sha256sum sed grep python3; do need "$d"; done

CHECK=0
SKIA_ONLY=0
ASE_TAG_OVERRIDE=""
for a in "$@"; do
	case "$a" in
	--check | -n) CHECK=1 ;;
	--skia-only) SKIA_ONLY=1 ;;
	--help | -h)
		sed -n '2,13p' "$0"
		exit 0
		;;
	v[0-9]*) ASE_TAG_OVERRIDE="$a" ;;
	*) die "unknown arg: $a" ;;
	esac
done

api() { curl -sSL -H "Accept: application/vnd.github+json" "$1"; }

# --- currently pinned values (read from manifest) ---
cur_tag=$(grep -m1 -oE 'tag: v[0-9.]+' "$MANIFEST" | sed 's/tag: //')
cur_tag="${cur_tag#v}"

# --- aseprite version ---
if [[ -n "$ASE_TAG_OVERRIDE" ]]; then
	ASE_TAG="$ASE_TAG_OVERRIDE"
elif [[ $SKIA_ONLY -eq 1 ]]; then
	ASE_TAG="v$cur_tag"
else
	ASE_TAG=$(api "https://api.github.com/repos/$ASE_REPO/releases/latest" | jq -r '.tag_name')
	[[ "$ASE_TAG" != "null" && -n "$ASE_TAG" ]] || die "failed to fetch latest aseprite release"
fi

# commit sha for tag
ASE_COMMIT=$(api "https://api.github.com/repos/$ASE_REPO/git/refs/tags/$ASE_TAG" | jq -r '.object.sha')
[[ "$ASE_COMMIT" != "null" && -n "$ASE_COMMIT" ]] || die "failed to resolve commit for $ASE_TAG"

# release date (YYYY-MM-DD); fall back to today if missing (e.g. overridden tag not = latest)
ASE_DATE=$(api "https://api.github.com/repos/$ASE_REPO/releases/tags/$ASE_TAG" |
	jq -r '.published_at // empty' | cut -dT -f1)
[[ -z "$ASE_DATE" || "$ASE_DATE" == "null" ]] && ASE_DATE=$(date +%F)

# --- skia branch from INSTALL.md at target tag ---
SKIA_BRANCH=$(curl -sSL "https://raw.githubusercontent.com/$ASE_REPO/$ASE_TAG/INSTALL.md" |
	grep -oE 'aseprite-m[0-9]+' | head -1)
[[ -n "$SKIA_BRANCH" ]] || die "no skia branch found in INSTALL.md of $ASE_TAG"
SKIA_M="${SKIA_BRANCH#aseprite-}" # e.g. m124

# find skia release tag whose name starts with "<m>-"
SKIA_TAG=$(api "https://api.github.com/repos/$SKIA_REPO/releases" |
	jq -r --arg m "$SKIA_M" '.[] | select(.tag_name | startswith($m + "-")) | .tag_name' | head -1)
[[ -n "$SKIA_TAG" ]] || die "no skia release matching $SKIA_M"

SKIA_URL="https://github.com/$SKIA_REPO/releases/download/$SKIA_TAG/$SKIA_ASSET"
SKIA_ZIP="/tmp/skia-bump-$$.zip"
curl -sSL "$SKIA_URL" -o "$SKIA_ZIP"
SKIA_SHA=$(sha256sum "$SKIA_ZIP" | cut -d' ' -f1)
rm -f "$SKIA_ZIP"
[[ -n "$SKIA_SHA" ]] || die "failed to hash skia asset"

if [[ $SKIA_ONLY -eq 0 ]]; then
	# --- runtime version (latest branch on flathub) ---
	RUNTIME_VER=$(flatpak remote-ls flathub --system --runtime 2>/dev/null |
		awk -v r="$RUNTIME" '$2==r {print $3}' | sort -uV | tail -1)
	[[ -z "$RUNTIME_VER" ]] && RUNTIME_VER="$RUNTIME_FALLBACK"
else
	# keep existing runtime version
	RUNTIME_VER=$(grep -m1 -oE "runtime-version: '[0-9.]+'" "$MANIFEST" | grep -oE "[0-9.]+")
fi

echo "aseprite:  $ASE_TAG  commit=$ASE_COMMIT  date=$ASE_DATE"
echo "skia:      $SKIA_TAG"
echo "skia url:  $SKIA_URL"
echo "skia sha:  $SKIA_SHA"
echo "runtime:   $RUNTIME_VER"

if [[ $CHECK -eq 1 ]]; then
	python3 bump_edit.py --skia-only --skia-url "$SKIA_URL" --skia-sha "$SKIA_SHA" --dry-run
else
	python3 bump_edit.py --skia-url "$SKIA_URL" --skia-sha "$SKIA_SHA" \
		--runtime "$RUNTIME_VER" --ase-tag "$ASE_TAG" --ase-commit "$ASE_COMMIT" --date "$ASE_DATE"
fi

echo "bumped -> $ASE_TAG ($SKIA_TAG), runtime $RUNTIME_VER"
