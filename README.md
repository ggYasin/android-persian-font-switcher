# Persian Font Switcher

[![Validate module](https://github.com/ggYasin/android-persian-font-switcher/actions/workflows/validate.yml/badge.svg)](https://github.com/ggYasin/android-persian-font-switcher/actions/workflows/validate.yml)

An open-source KernelSU Next module with an offline WebUI for choosing Android's Persian/Arabic-script fallback font while keeping the currently selected Latin `sans-serif` font.

Install once, open the module's WebUI, preview a font, select it, and reboot. The module changes only four generated systemless-overlay files; it does not hook apps or rewrite the physical system partition.

## Features

- Mobile-friendly offline KernelSU Next WebUI with real embedded font previews.
- Vazirmatn, Estedad, and Sahel Regular/Bold choices.
- Persian samples, ZWNJ/half-space words, Persian and Latin digits, and mixed-script previews.
- System Default option that stops mounting the generated font overlay.
- Strict manifest/ID allowlisting and pinned SHA-256 checks before every change.
- Rollback-capable directory replacement with `skip_mount` as an interruption fail-safe.
- Official KernelSU Next persistent module configuration, with a module-local fallback.
- No CDN, network request, analytics, telemetry, daemon, Zygisk, LSPosed, SELinux policy, system property, or boot-time service.

The initial selection is Vazirmatn. Font changes officially take effect only after reboot; hot replacement is intentionally unsupported.

## Bundled fonts

| Font | Version and variant | Upstream | Author/project | License |
| --- | --- | --- | --- | --- |
| Vazirmatn | 33.003, UI Non-Latin | [release](https://github.com/rastikerdar/vazirmatn/releases/tag/v33.003) | Saber Rastikerdar / Vazirmatn Project Authors | OFL-1.1 |
| Estedad | 8.5, static upstream builds | [release](https://github.com/aminabedi68/Estedad/releases/tag/8.5) | Fontamin / Estedad Project Authors | OFL-1.1 |
| Sahel | 3.4.0, Without Latin | [release](https://github.com/rastikerdar/sahel-font/releases/tag/v3.4.0) | Saber Rastikerdar | OFL-1.1; upstream Apache-2.0 notice retained |

Vazirmatn and Sahel use their official non-Latin variants. Estedad does not publish an equivalent static non-Latin release, so this project keeps its official Regular/Bold binaries unchanged. Android resolves ordinary Latin through the primary selected sans-serif family before consulting the Arabic-script fallback; the module never replaces Roboto or another selected Latin family.

Exact file and source-archive hashes live in [`webroot/font-manifest.json`](webroot/font-manifest.json), and each font directory contains its upstream license. See [third-party notices](THIRD_PARTY_NOTICES.md) for provenance and the IRANSans exclusion.

## Supported systems

This release supports:

- Android 12–16 / API 31–36;
- ROMs using the verified complete AOSP four-file `und-Arab` compact/elegant fallback layout;
- the tested crDroid 12 / Android 16 layout;
- KernelSU Next Manager v3.0.0 or newer for the persistent config backend (audited against v3.3.0 / build 33214);
- a compatible systemless mount provider that re-reads the module's `system/` tree at boot.

Magic Mount-style providers are the intended dynamic-switching architecture. Magic Mount-rs is one known compatible provider. The module does not require that specific provider, inspect its settings, or change `config.toml`.

Some overlayfs metamodules copy module payloads to a separate content root only during installation. Post-install WebUI switching is not currently claimed for those providers. See [compatibility](docs/COMPATIBILITY.md) for the precise boundary.

The installer checks the API, `/system/etc/fonts.xml`, the `und-Arab` family, and all four files before installing. A matching Android version alone is not sufficient, so vendor ROMs with a different layout fail safely.

## Android files overlaid

For a selected font, Regular and Bold are duplicated to:

```text
/system/fonts/NotoNaskhArabicUI-Regular.ttf
/system/fonts/NotoNaskhArabicUI-Bold.ttf
/system/fonts/NotoNaskhArabic-Regular.ttf
/system/fonts/NotoNaskhArabic-Bold.ttf
```

These are Arabic-script fallbacks, so Persian, Arabic, Urdu, and other languages using the same fallback can all change. Apps, games, or web pages that explicitly bundle and select their own font can ignore Android's fallback.

## Install and use

1. Remove or disable another font module that overlays the same targets, then reboot.
2. Confirm a compatible KernelSU systemless mount provider is active.
3. Open KernelSU Next → Modules → Install from storage.
4. Select `Persian-Font-Switcher-v0.1.0-rc2.zip` and reboot.
5. Open Persian Font Switcher from the module card.
6. Preview and select a font.
7. Reboot when convenient.

The installer detects the legacy `vazirmatn_persian_fallback`, the archived `Vazirmatn-Regular` module, and any enabled module containing one of the four target files. Conflicts are reported but never removed or modified automatically.

The WebUI never reboots the phone itself. KernelSU Next v3.3.0 has no dedicated documented WebUI reboot method, so the module only displays a reboot-required status.

## System Default and uninstall

System Default creates the standard module `skip_mount` marker, removes the four generated overlay files, preserves the WebUI, and saves `system-default`. After reboot, the ROM's original fonts are visible again.

To uninstall completely, disable or remove Persian Font Switcher in the root manager and reboot.

## Security model

KernelSU Next's WebUI bridge can execute root commands, so this project treats the WebUI as privileged code:

- `ksu.moduleInfo()` must return the exact module ID and path.
- Only fixed module-local scripts can be executed.
- A font ID must match a strict character pattern and the bundled manifest in JavaScript and shell.
- Names, descriptions, paths, and arbitrary user text are never inserted into commands.
- Font paths are canonical and hashes are checked again before copying.
- A restrictive Content Security Policy permits only module-local scripts, styles, fonts, and manifest reads.
- There are no remote links or requests inside the privileged WebUI.

See [SECURITY.md](SECURITY.md) and [architecture](docs/ARCHITECTURE.md) for details.

## Build and validate

Linux prerequisites:

- POSIX shell and standard tools;
- `zip`, `unzip`, `file`, and `sha256sum`;
- Python 3 with `fonttools`;
- Node.js is optional and enables an additional JavaScript syntax check.

```sh
python3 -m pip install 'fonttools>=4.46,<5'
./scripts/build.sh
./scripts/validate.sh ./Persian-Font-Switcher-v0.1.0-rc2.zip
```

The build is deterministic: it uses an explicit payload list, normalized permissions/timestamps, and no generated network dependencies. Validation checks the manifest, licenses, TTF metadata, Regular/Bold weight classes, shaping tables, Persian glyphs, ZWNJ, digits, checksums, preview identity, WebUI policy, shell/JS syntax, attack inputs, System Default, ZIP modes, exact root paths, and clean extraction. An installer regression test also forces extracted scripts to `0644`, runs the real `customize.sh` against isolated fake Android roots, verifies initial mapping, and checks final runtime modes are `0755`.

The validated `v0.1.0-rc2` ZIP SHA-256 is:

```text
55f34bb23d37f8f3d6219f85194ea7aada3ef9ddbdc8a4e46cbd2bcb39445de1
```

## Contributing

- To add a font, follow [Adding fonts](docs/ADDING_FONTS.md). Only official upstream files with clear redistribution rights are accepted.
- To add another ROM mapping, provide upstream or device evidence for its active font configuration and extend capability checks rather than weakening them.
- Do not submit commercial fonts, unlicensed mirrors, font hooks, remote WebUI dependencies, or code that changes root-hiding/integrity settings.

## History and credits

Persian Font Switcher is authored and maintained by **Yasin Fadaee / [@ggYasin](https://github.com/ggYasin)**.

The existing [`v33.003` release](https://github.com/ggYasin/android-persian-font-switcher/releases/tag/v33.003) is preserved as the historical Vazirmatn-only static module. Project versions from `0.1.0` onward use semantic versioning independently of bundled font versions.

Thanks to Saber Rastikerdar, Fontamin, the Estedad and Vazirmatn project authors, their contributors, KernelSU Next, and systemless mount-provider maintainers.
