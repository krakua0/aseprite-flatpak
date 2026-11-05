#!/usr/bin/env bash
# test.sh — invariant checks for this manifest repo. No framework, no network by default.
#
# Usage:
#   ./test.sh            # offline: structure + cross-file consistency + linters
#   ./test.sh --net      # also check upstream (tag->commit, skia asset, runtime branch)
#   ./test.sh -v         # print every check command's output
#
# Exit 0 = all required checks pass. Expected-failure checks (xfail) are reported
# separately and never fail the run; an xfail that starts passing is reported as
# XPASS so the note can be removed.
#
# Requires: yq mikefarah jq sed grep coreutils (+ optional: shellcheck, ruff,
# python3, desktop-file-validate, appstreamcli, flatpak)

# shall()/nn()/runtime_quote_styles() are invoked indirectly through t()/x()/eval
# shellcheck disable=SC2329

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 2

MANIFEST=aseprite.yaml
METAINFO=aseprite.metainfo.xml
DESKTOP=aseprite.desktop
MIMEXML=aseprite.mime.xml

NET=0
VERBOSE=0
for a in "$@"; do
	case "$a" in
	--net) NET=1 ;;
	-v | --verbose) VERBOSE=1 ;;
	-h | --help)
		sed -n '2,16p' "$0"
		exit 0
		;;
	*)
		echo "unknown arg: $a" >&2
		exit 2
		;;
	esac
done

pass=0
fail=0
skip=0
xfail=0
xpass=0
failed_list=()

yqr() { yq -r "$1" "$MANIFEST"; }              # yq field read (bare value)
yqj() { yq -o=json "$MANIFEST" | jq -r "$1"; } # yq field read (query via jq)
# indent multi-line command output for readable failures
ind() {
	local out=$1
	printf '        %s\n' "${out//$'\n'/$'\n'        }"
}

# t <name> <cmd...> : pass if cmd exits 0
t() {
	local name=$1
	shift
	local out rc
	out=$("$@" 2>&1)
	rc=$?
	if [[ $rc -eq 0 ]]; then
		pass=$((pass + 1))
		echo "ok    $name"
	else
		fail=$((fail + 1))
		failed_list+=("$name")
		echo "FAIL  $name"
		[[ -n "$out" ]] && ind "$out"
	fi
}

# x <name> <cmd...> : expected failure (known gap); XPASS when it starts passing
x() {
	local name=$1
	shift
	local out rc
	out=$("$@" 2>&1)
	rc=$?
	if [[ $rc -ne 0 ]]; then
		xfail=$((xfail + 1))
		echo "xfail $name"
		[[ $VERBOSE -eq 1 && -n "$out" ]] && ind "$out"
	else
		xpass=$((xpass + 1))
		echo "XPASS $name  <- known gap looks fixed; remove the xfail"
	fi
}

# s <name> <cmd...> : skip when a probe command fails (missing tool etc.)

shall() { # assert a shell test expression
	eval "$1"
}

nn() { # assert a value is present
	[[ -n "${1// /}" && "$1" != "null" ]]
}

# ---------------------------------------------------------------- prereqs
for tool in yq jq sed grep; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "ERROR: missing dep: $tool" >&2
		exit 2
	}
done
yq --version 2>&1 | grep -q mikefarah || {
	echo "ERROR: needs mikefarah/yq (v4), found: $(yq --version 2>&1)" >&2
	exit 2
}

app_id=$(yqr '.app-id')
runtime=$(yqr '.runtime-version')
ase_tag=$(yqr '.modules[0].sources[0].tag')
ase_commit=$(yqr '.modules[0].sources[0].commit')
skia_url=$(yqr '.modules[0].sources[1].url')
skia_sha=$(yqr '.modules[0].sources[1].sha256')
cmd=$(yqr '.command')
build_args=$(yqr '.modules[0].build-args // [] | join(" ")')
buildsystem=$(yqr '.modules[0].buildsystem')
only_arches=$(yqj '.modules[0]["only-arches"] // [] | join(",")')
rel_date=$(sed -n 's:.*<release version="[^"]*" date="\([^"]*\)".*:\1:p' "$METAINFO")

# check_tool <name> <cmd...> : run only if the command exists, else skip
check_tool() {
	local name=$1
	shift
	if ! command -v "$1" >/dev/null 2>&1; then
		skip=$((skip + 1))
		echo "skip  $name (missing: $1)"
		return
	fi
	t "$name" "$@"
}

# ---------------------------------------------------------------- manifest schema
t "manifest: parses as YAML" yq -o=json . "$MANIFEST"
t "manifest: app-id shape" shall "[[ '$app_id' =~ ^[a-z][a-z0-9_]*(\.[A-Za-z0-9_]+)+\$ ]]"
t "manifest: runtime-version is a flathub branch" shall "[[ '$runtime' =~ ^[0-9]{2}\.[0-9]{2}\$ ]]"
t "manifest: sdk matches runtime" shall "[[ \"$(yqr '.sdk')\" == org.freedesktop.Sdk ]]"
t "manifest: strip *debug* from final image" yqr '.cleanup[]' | grep -qx /lib/debug
t "manifest: no hardcoded secrets in build-args" shall \
	"[[ ! '$build_args' =~ (TOKEN|SECRET|KEY)= ]]"
t "manifest: module buildsystem is cmake-ninja" shall "[[ '$buildsystem' == cmake-ninja ]]"

# sources
t "manifest: aseprite tag present" nn "$ase_tag"
t "manifest: aseprite commit present" nn "$ase_commit"
t "manifest: skia url present" nn "$skia_url"
t "manifest: aseprite tag shape" shall "[[ '$ase_tag' =~ ^v[0-9]+(\.[0-9]+)+\$ ]]"
t "manifest: aseprite commit is a full sha" shall "[[ '$ase_commit' =~ ^[0-9a-f]{40}\$ ]]"
t "manifest: archive url is https" shall "[[ '$skia_url' =~ ^https:// ]]"
t "manifest: skia sha256 shape" shall "[[ '$skia_sha' =~ ^[0-9a-f]{64}\$ ]]"
t "manifest: every file source exists on disk" bash -c \
	"yq -r '.modules[0].sources[] | select(.type==\"file\") | .path' '$MANIFEST' | while read -r p; do test -f \"\$p\" || exit 1; done"
x "manifest: x64-only skia asset declares only-arches" shall \
	"[[ ! '$skia_url' =~ x64 || '$only_arches' == *x86_64* ]]"

# ---------------------------------------------------------------- cross-file consistency
t "app-id == build.sh APP_ID" bash -c "grep -q '^APP_ID=\"$app_id\"' build.sh"
t "app-id == metainfo <id>" bash -c "grep -q '<id>$app_id</id>' $METAINFO"
t "app-id == desktop Icon=" bash -c "grep -q '^Icon=$app_id\$' $DESKTOP"
t "metainfo launchable == app-id.desktop" bash -c "grep -q '<launchable type=\"desktop-id\">$app_id.desktop</launchable>' $METAINFO"
t "desktop Exec uses manifest command '$cmd'" bash -c "grep -q '^Exec=$cmd ' $DESKTOP"
t "desktop Exec forwards file args (%F)" bash -c "grep -q '%F' $DESKTOP"
t "desktop StartupWMClass matches manifest command" bash -c "grep -q '^StartupWMClass=$cmd\$' $DESKTOP"

meta_rel=$(sed -n 's:.*<release version="\([^"]*\)".*:\1:p' "$METAINFO")
t "metainfo <release version> == manifest tag" shall "[[ '$meta_rel' == '${ase_tag#v}' ]]"

# every mime type we install must be listed in the desktop file
t "mime types are declared in desktop MimeType=" bash -c \
	"grep -o 'type=\"[^\"]*\"' $MIMEXML | cut -d'\"' -f2 | while read -r m; do grep -q \"\$m\" $DESKTOP || exit 1; done"

# build.sh + bump.sh + bump_edit.py read the runtime pin from the manifest.
# yq rewrites '25.08' as "25.08", so the readers must not depend on the quote
# style: they match the line, then extract the value. Canonical two-stage form:
RUNTIME_LINE='^runtime-version:'
RUNTIME_VALUE='[0-9]{2}\.[0-9]{2}'
t "manifest: runtime line is grep-able" bash -c \
	"grep -m1 -E '$RUNTIME_LINE' $MANIFEST | grep -qE '$RUNTIME_VALUE'"
t "build.sh uses the canonical runtime reader" grep -qF -- \
	"grep -m1 -E '$RUNTIME_LINE'" build.sh
t "bump.sh uses the canonical runtime reader" grep -qF -- \
	"grep -m1 -E '$RUNTIME_LINE'" bump.sh
# the runtime bump must be constrained by the declared sdk-extensions, otherwise
# it pins a branch the manifest cannot build on (Platform 26.08 has no llvm20)
t "bump.sh intersects runtime branches with sdk-extensions" bash -c \
	"grep -q 'sdk-extensions:' bump.sh && grep -q 'flathub_branches \"\$ext\"' bump.sh"

# ---------------------------------------------------------------- bumper regression
# runtime_quote_styles(): the runtime edit must rewrite both '25.08' and
# "25.08" in place. Quote drift is what broke the bumper silently, and the
# manifest is free to be restyled by yq, so neither style may be assumed.
runtime_quote_styles() {
	python3 - <<'PY'
import re
import sys

import bump_edit

_, pattern, template = bump_edit.EDITS["runtime-version"]
bad = []
for q in ("'", '"'):
	src = f"runtime-version: {q}25.08{q}\n"
	out, n = re.subn(pattern, template.format(runtime="26.08"), src, count=1)
	if n != 1 or out != f"runtime-version: {q}26.08{q}\n":
		bad.append(f"quote {q}: n={n} out={out!r}")
if bad:
	print("\n".join(bad))
	sys.exit(1)
PY
}

if command -v python3 >/dev/null 2>&1; then
	t "bump_edit.py no-op dry-run edits nothing" python3 bump_edit.py --dry-run \
		--skia-url "$skia_url" --skia-sha "$skia_sha" --runtime "$runtime" \
		--ase-tag "$ase_tag" --ase-commit "$ase_commit" \
		--date "$rel_date"
	t "bump_edit.py runtime edit tolerates both quote styles" runtime_quote_styles
	# --check must exercise the whole edit set, otherwise a drifted pattern is
	# only caught when bump.sh actually writes the files.
	t "bump.sh --check validates every field (not only skia)" bash -c \
		"grep -q -- '--runtime \"\$RUNTIME_VER\"' bump.sh"
else
	skip=$((skip + 1))
	echo "skip  bump_edit.py checks (missing: python3)"
fi

# ---------------------------------------------------------------- external validators
check_tool "desktop-file-validate desktop file" desktop-file-validate "$DESKTOP"
check_tool "shellcheck scripts" shellcheck -x build.sh bump.sh test.sh
check_tool "ruff python" ruff check bump_edit.py
x "appstreamcli metainfo (Flathub-bound fixes pending)" \
	appstreamcli validate --pedantic "$METAINFO"

# ---------------------------------------------------------------- network
if [[ $NET -eq 1 ]]; then
	t "upstream: tag $ase_tag resolves to pinned commit" bash -c \
		"git ls-remote https://github.com/aseprite/aseprite refs/tags/$ase_tag | cut -f1 | grep -qx $ase_commit"
	t "upstream: skia asset URL responds 200" curl -sfIL -o /dev/null "$skia_url"
	# The pinned branch must be published for the base runtime AND every declared
	# sdk-extension. That intersection, not the newest Platform branch, is what
	# bump.sh resolves.
	# installation must be named explicitly or flatpak aborts with
	# "Remote 'flathub' found in multiple installations" (same as bump.sh)
	remote_runtimes=$(flatpak remote-ls flathub --system --runtime 2>/dev/null ||
		flatpak remote-ls flathub --user --runtime 2>/dev/null)
	branches_of() { printf '%s\n' "$remote_runtimes" | awk -F'\t' -v r="$1" '$2 == r { print $NF }' | sort -u; }
	common=$(branches_of "$(yqr '.runtime')")
	for ext in $(yqr '.sdk-extensions // [] | .[]'); do
		common=$(comm -12 <(printf '%s\n' "$common") <(branches_of "$ext"))
	done
	common_file=$(mktemp)
	printf '%s\n' "$common" >"$common_file"
	t "upstream: pinned runtime is published for runtime + every sdk-extension" \
		grep -qx "$runtime" "$common_file"
	rm -f "$common_file"
	x "upstream: pinned runtime is the newest Platform branch (gap: llvm20 has no 26.08)" bash -c \
		"{ flatpak remote-ls flathub --system --runtime 2>/dev/null || flatpak remote-ls flathub --user --runtime 2>/dev/null; } | awk -F'\\t' -v r=\"$(yqr '.runtime')\" '\$2 == r { print \$NF }' | sort -uV | tail -1 | grep -qx '$runtime'"
else
	skip=$((skip + 4))
	echo "skip  4 upstream checks (re-run with --net)"
fi

# ---------------------------------------------------------------- result
echo
echo "pass=$pass fail=$fail xfail=$xfail xpass=$xpass skip=$skip"
if [[ $fail -gt 0 ]]; then
	printf 'failed: %s\n' "${failed_list[@]}"
	exit 1
fi
exit 0
