# Aseprite flatpak-builder manifest

A manifest to build `aseprite` as a `flatpak` with a proper `.desktop` launcher icon.

> [!WARNING]
> + Only works for `x86_64`
> + Uses prebuilt skia binaries.

> [!IMPORTANT]
> Aseprite version: v1.3.13

# Requirements

## Host

```
git
flatpak-builder
```

## Flatpak

```
org.freedesktop.Sdk.Extension.llvm20/x86_64/24.08
```

# Build

```bash
#!/usr/bin/env bash
source build.sh
flatpak.build.deps
flatpak.build.clean aseprite.yaml
flatpak.bundle
flatpak install ./org.krakua0.Aseprite.flatpak
# or just `flatpak-builder --force-clean --system --install-deps-from=flathub --install aseprite.yaml`
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
