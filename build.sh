#!/usr/bin/env bash

APP_ID="org.krakua0.Aseprite"
MANIFEST="aseprite.yaml"
BUILD_DIR="builddir" # flathub-build wrapper hardcodes this
REPO_DIR="repo"      # wrapper exports here via --repo=repo
BRANCH="stable"
BUNDLE_FILENAME="${APP_ID}.flatpak"
RUNTIME_REPO="--runtime-repo=https://flathub.org/repo/flathub.flatpakrepo"

flatpak.build.deps() {
	# All installs target --user to match flathub-build wrapper (FLATPAK_USER_DIR=host ~/.local/share/flatpak).
	# Explicit --user avoids "remote found in multiple installations" ambiguity.
	flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
	# org.flatpak.Builder = Flathub-maintained builder; bare flatpak-builder is deprecated.
	flatpak install --user -y --noninteractive flathub org.flatpak.Builder
	# Pre-install runtime + sdk + llvm20 ext so --install-deps-from=flathub finds them and skips
	# its own (sandbox-broken) dep install. Version read from manifest (kept in sync by bump.sh).
	local rt
	rt=$(grep -m1 -oE "runtime-version: '[0-9.]+'" "$MANIFEST" | grep -oE "[0-9.]+")
	rt="${rt:-25.08}"
	flatpak install --user -y --noninteractive flathub \
		"org.freedesktop.Platform/x86_64/$rt" \
		"org.freedesktop.Sdk/x86_64/$rt" \
		"org.freedesktop.Sdk.Extension.llvm20/x86_64/$rt"
}

flatpak.build() {
	# Usage: flatpak.build [extra flatpak-builder args...]
	#
	# flathub-build wrapper sets FLATPAK_USER_DIR + FLATPAK_BINARY so --user + --install-deps-from
	# resolve against the HOST installation, not Builder's sandbox. Raw --command=flatpak-builder
	# skips those env vars → "No remote refs found for flathub".
	# Wrapper injects: --force-clean --user --install-deps-from=flathub --repo=repo builddir
	# --default-branch=stable keeps exported refs aligned with flatpak.bundle.
	flatpak run --command=flathub-build org.flatpak.Builder \
		--install --default-branch="$BRANCH" "$@" "$MANIFEST"
}

flatpak.build.clean() {
	rm -rf "$BUILD_DIR" "$REPO_DIR"
	flatpak.build "$@"
}

flatpak.bundle() {
	[[ -d "$REPO_DIR" ]] || {
		echo "ERROR: $REPO_DIR missing — run flatpak.build first." >&2
		return 1
	}
	# flathub-build wrapper already ran build-export into $REPO_DIR during the build,
	# so only build-bundle remains.
	echo "Creating single-file bundle ($BUNDLE_FILENAME)..."
	flatpak build-bundle "$REPO_DIR" "$BUNDLE_FILENAME" "$APP_ID" "$BRANCH" "$RUNTIME_REPO" || {
		echo "ERROR: flatpak build-bundle failed." >&2
		return 1
	}
	echo "Successfully created $BUNDLE_FILENAME"
}

export -f flatpak.build.deps
export -f flatpak.build
export -f flatpak.build.clean
export -f flatpak.bundle
