# Aseprite flatpak-builder manifest

A manifest to build `aseprite` as a `flatpak` with a proper `.desktop` launcher icon.

> [!WARNING]
> + Only works for `x86_64`
> + Uses prebuilt skia binaries.

> [!IMPORTANT]
> Aseprite version: v1.3.18.1

# Requirements

## Host

```
git
flatpak          # org.flatpak.Builder installed by flatpak.build.deps
```

## Flatpak

```
org.freedesktop.Sdk.Extension.llvm20/x86_64/<runtime-version in manifest>
```

# Build

```bash
source build.sh
flatpak.build.deps        # installs org.flatpak.Builder + runtime/sdk/llvm20 to --user
flatpak.build.clean       # wipes builddir/ repo/ then builds + installs aseprite.yaml
flatpak.bundle            # bundles repo/ (exported by builder) -> org.krakua0.Aseprite.flatpak
flatpak install ./org.krakua0.Aseprite.flatpak
```

# Version bump

`./bump.sh` fetches the latest aseprite release + matching skia prebuilt (branch
read from that release's `INSTALL.md`) + latest flathub runtime, then rewrites
`aseprite.yaml`, `aseprite.metainfo.xml`, and this README in place.

```bash
./bump.sh                 # bump to latest aseprite release
./bump.sh --check         # dry-run: print resolved values, edit nothing
./bump.sh v1.3.18.1       # pin to a specific tag
./bump.sh --skia-only     # re-fetch skia asset for the currently-pinned tag
```

# Plans

+ [ ] Better templating for `flatpak-builder` manifest and scripts
	+ [ ] `.env` files with reusable values
+ [ ] Option to build from
	+ [ ] latest stable release version of `aseprite`
	+ [ ] sources
	+ [ ] remote pre-built binaries
+ [ ] `i18n`
	+ [ ] More languages in `.desktop`
	+ [ ] Build script messages
+ [ ] Script to push bundle into a local `flatpak` repo for home-labbers and self-hosters?
