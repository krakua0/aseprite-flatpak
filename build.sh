#!/usr/bin/env bash

flatpak.build.deps() {
	flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
	# flatpak --system install flathub -y --noninteractive runtime/org.freedesktop.Platform.ffmpeg-full/x86_64/24.08
	flatpak --system install flathub -y --noninteractive org.freedesktop.Sdk.Extension.llvm20/x86_64/24.08
	return $?
}

flatpak.build() {
	# flatpak-builder --force-clean build aseprite.yaml
	# flatpak-builder --force-clean "$@" build aseprite.yaml
	flatpak-builder --force-clean --system --install-deps-from=flathub --install "$@"
	return $?
}

flatpak.bundle() {
	APP_ID="org.krakua0.Aseprite"
	BUILD_DIR="build"
	REPO_DIR="repo"
	BUNDLE_FILENAME="${APP_ID}.flatpak"
	BRANCH="stable"

	# Optional: Add the Flathub runtime repo for convenience during installation
	RUNTIME_REPO="--runtime-repo=https://flathub.org/repo/flathub.flatpakrepo"

	# 1. Clean up previous repository (pragmatic for quick rebuilds)
	rm -rf "$REPO_DIR"

	# 2. Export the build directory into a local repository
	echo "Exporting build to local repository ($REPO_DIR)..."
	flatpak build-export "$REPO_DIR" "$BUILD_DIR" "$BRANCH" || { 
		echo "ERROR: flatpak build-export failed." 
		exit 1 
	}

	# 3. Create the single-file bundle (.flatpak)
	echo "Creating single-file bundle ($BUNDLE_FILENAME)..."
	flatpak build-bundle "$REPO_DIR" "$BUNDLE_FILENAME" "$APP_ID" "$BRANCH" "$RUNTIME_REPO" || { 
		echo "ERROR: flatpak build-bundle failed." 
		exit 1 
	}

	echo "Successfully created $BUNDLE_FILENAME"
	return $?
}

export -f flatpak.build.deps
export -f flatpak.build
export -f flatpak.bundle

