# Aseprite flatpak-builder manifest

A manifest to build aseprite for flatpak.

> [!WARNING]
> + Only works for `x86_64`
> + Uses prebuilt skia binaries.

Aseprite version: v1.3.13

# Requirements

## Host

```
git
flatpak-builder
```

## Flatpak

`org.freedesktop.Sdk.Extension.llvm20/x86_64/24.08`

# Build

```bash
#!/usr/bin/env bash
source build.sh
flatpak.build.deps
flatpak.build.clean aseprite.yaml # or just `flatpak-builder --force-clean --system --install-deps-from=flathub --install aseprite.yaml`
flatpak.bundle
```

