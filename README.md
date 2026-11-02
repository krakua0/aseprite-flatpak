# Aseprite flatpak-builder manifest

A manifest to build `aseprite` as a `flatpak` with a proper `.desktop` launcher icon.

> [!WARNING]
>
> - Only works for `x86_64`
> - Uses prebuilt skia binaries.

The pinned Aseprite version lives in one place only: `aseprite.yaml` →
`modules[0].sources[0].tag` / `.commit`. `./bump.sh` rewrites it.

## Requirements

### Build (host)

```text
flatpak          # org.flatpak.Builder is installed by flatpak.build.deps
```

### Version bump (host)

```text
git              # resolves tags + commits over https, no GitHub API rate limit
curl jq sha256sum sed grep python3
flatpak          # optional: discovers the newest flathub runtime branch
```

### Flatpak

```text
org.freedesktop.Sdk.Extension.llvm20/x86_64/<runtime-version in manifest>
```

## Build

```bash
source build.sh
flatpak.build.deps        # installs org.flatpak.Builder + runtime/sdk/llvm20 to --user
flatpak.build.clean       # wipes builddir/ repo/ then builds + installs aseprite.yaml
flatpak.bundle            # bundles repo/ (exported by builder) -> org.krakua0.Aseprite.flatpak
flatpak install ./org.krakua0.Aseprite.flatpak
```

## Usage

Useful paths:

```text
~/.var/app/org.krakua0.Aseprite   # Flatpak app files prefix
└── /config                       # Flatpak app config prefix
    └── /aseprite                 # Aseprite. Similar to `~/.config/aseprite`
        ├── /extensions           # Extensions. Usually `.lua`
        └── /scripts              # Scripts. Usually `.lua`
```

## Version bump

`./bump.sh` fetches the latest aseprite release + matching skia prebuilt (branch read from that release's `INSTALL.md`) + latest flathub runtime, then rewrites `aseprite.yaml` and `aseprite.metainfo.xml` in place.

```bash
./bump.sh                 # bump to latest aseprite release
./bump.sh --check         # dry-run: print resolved values, edit nothing
./bump.sh v1.3.18.1       # pin to a specific tag
./bump.sh --skia-only     # re-fetch skia asset for the currently-pinned tag
```

## Plans

- [ ] Better templating for `flatpak-builder` manifest and scripts
  - [ ] `.env` files with reusable values
- [ ] Option to build from
  - [ ] latest stable release version of `aseprite`
  - [ ] sources
  - [ ] remote pre-built binaries
- [ ] `i18n`
  - [ ] More languages in `.desktop`
  - [ ] Build script messages
- [ ] Script to push bundle into a local `flatpak` repo for home-labbers and self-hosters?
