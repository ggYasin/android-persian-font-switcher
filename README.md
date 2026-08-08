# Persian Font Switcher

[![Validate module](https://github.com/ggYasin/android-persian-font-switcher/actions/workflows/validate.yml/badge.svg)](https://github.com/ggYasin/android-persian-font-switcher/actions/workflows/validate.yml)

An open-source KernelSU Next module with an offline WebUI for choosing Android's Persian/Arabic-script fallback font while preserving the selected Latin `sans-serif` family.

The module changes only the four known AOSP compact/elegant Arabic fallback paths. It has no daemon, service script, Zygisk component, font hook, network access, telemetry, or physical `/system` write.

## WebUI

- Searchable list with real embedded Regular/Bold Persian previews.
- Separate **Active** effective-mount state, **Selected** pending state, and restart-required status.
- One explicit Apply button, System Default, Reboot now, and Later.
- FontLoader enabled/disabled/pending/not-detected status.
- Custom Regular+Bold import through KernelSU Next's Android file picker and root-backed binary stream.
- Local SFNT structure, shaping-table, weight, size, and visible Persian glyph validation before import.

The active font is derived from SHA-256 hashes of all four effective `/system/fonts` targets in PID 1's mount namespace when available. It is never inferred only from saved configuration. Because the project deliberately does not copy or pin a ROM's original proprietary/system font hashes, a System Default result may honestly appear as “System default or unrecognized.”

## Bundled fonts

| Font | Version / variant | Author | License |
| --- | --- | --- | --- |
| Vazirmatn | 33.003 UI Non-Latin | Saber Rastikerdar / project authors | OFL-1.1 |
| Estedad | 8.5 static | Amin Abedi / project authors | OFL-1.1 |
| Sahel | 3.4.0 Without Latin | Saber Rastikerdar | OFL-1.1; retained Apache notice |
| Shabnam | 5.0.1 Without Latin | Saber Rastikerdar | OFL-1.1; embedded upstream notices |
| Samim | 4.0.5 Without Latin | Saber Rastikerdar | OFL-1.1; embedded upstream notices |
| Tanha | 0.10 Without Latin | Saber Rastikerdar | Public-domain/Apache/Bitstream terms in upstream LICENSE |
| Gandom | 0.8 Without Latin | Saber Rastikerdar | OFL-1.1; embedded upstream notices |
| Parastoo | 2.0.1 Web Without Latin | Saber Rastikerdar | OFL-1.1 |
| Mikhak | 3.4 static | Amin Abedi / project authors | OFL-1.1 |
| Cairo | 3.116 static | Mohamed Gaber / project authors | OFL-1.1 |
| Noto Sans Arabic | 2.013 unhinted static | Noto Project Authors | OFL-1.1 |
| Noto Kufi Arabic | 2.110 unhinted static | Noto Project Authors | OFL-1.1 |
| IBM Plex Sans Arabic | package 1.1.0 / font 1.005 | IBM / Bold Monday | OFL-1.1 |

Tanha and Gandom publish only one upstream weight. Their unchanged official Regular file is therefore used for both Android Regular and Bold targets; the WebUI and manifest disclose this limitation. Every other family has separate upstream Regular and Bold files.

Pinned sources, archive/commit references, exact font SHA-256 values, variants, authors, and license paths are in [`webroot/font-manifest.json`](webroot/font-manifest.json). Every redistributed font license is bundled beside its files.

IRANSans is not bundled. The supplied mirror's own README says rights must be obtained from FontIran, and the binaries identify FontIran/Moslem Ebrahimi with “All rights reserved.” A user who has a valid license may import their own Regular/Bold files locally; custom files are never committed, uploaded, or distributed by this project.

## Custom fonts

KernelSU Next Manager v3.1.0+ exposes the standard Android document picker and a binary file-output bridge. rc3 feature-detects that API, accepts exactly one Regular and one Bold file (maximum 16 MiB each), validates both in the WebUI, streams them to a random fixed staging location, and lets a trusted module script revalidate token, path, size, SFNT magic, and hashes.

Imported files are assigned a content-addressed `custom-…` ID and atomically persisted under:

```text
/data/adb/persian_font_switcher/custom-fonts/
```

That module-owned data directory survives KernelSU's whole-directory module update replacement. `customize.sh` rebuilds read-only WebUI preview copies on every update. Display names and file-picker paths never enter a shell command. Custom files remain the user's licensing responsibility.

## Why restart is required

Applying a selection atomically prepares the module's next `system/fonts` overlay and saves the pending ID. It does not claim to change live processes.

Magic Mount-rs binds the current source inode at boot. Replacing the module directory atomically does not retarget that live bind mount. Android also mmaps fonts and establishes a process-local system font map that cannot be replaced after initialization. Consequently:

- restarting only SystemUI does not update existing apps and may still inherit old zygote font state;
- a soft zygote restart without a supported provider remount still sees the old bind mount and is disruptive;
- the module does not perform ad-hoc runtime bind mounts or alter provider configuration.

The honest provider-agnostic choices are **Reboot now** or **Later**. Rebooting reruns the external mount provider before zygote, SystemUI, apps, and FontLoader initialize.

## FontLoader

[FontLoader](https://github.com/KernelSU-Modules-Repo/fontloader) remains a separate optional Zygisk module. It can be important on Android 12+ when an app later loses access to module font paths through mount-namespace hiding while fonts are lazily loaded. The WebUI detects module ID `fontloader` and reports enabled, disabled, pending install/removal, or not detected. Persian Font Switcher never installs, enables, disables, or configures it.

## Supported systems

- Android 12–16 / API 31–36.
- A complete AOSP `und-Arab` compact/elegant four-file layout verified by the installer.
- KernelSU Next Manager v3.1.0+ for custom import; v3.0.0+ remains sufficient for bundled selection/config persistence.
- A compatible systemless mount provider that rereads the module's `system/` tree at boot. Magic Mount-rs is a known compatible provider.

Vendor ROMs using different font configuration fail closed. The module never changes Magic Mount-rs configuration, KernelSU profiles, root hiding, integrity configuration, NeoZygisk, Vector, LSPosed, or TrickyStore.

## Android targets

```text
/system/fonts/NotoNaskhArabicUI-Regular.ttf
/system/fonts/NotoNaskhArabicUI-Bold.ttf
/system/fonts/NotoNaskhArabic-Regular.ttf
/system/fonts/NotoNaskhArabic-Bold.ttf
```

Persian, Arabic, Urdu, and other languages sharing the Arabic-script fallback may all change. Apps or web content explicitly selecting a bundled font can bypass Android's fallback.

## Install and use

1. Disable/remove another module overlaying these targets, then reboot.
2. Confirm a compatible KernelSU systemless mount provider is active.
3. Install `Persian-Font-Switcher-v0.1.0-rc3.zip` from KernelSU Next Modules.
4. Reboot, open the module WebUI, search/preview, choose a font, and tap Apply selection.
5. Reboot now or later when convenient.

System Default creates the standard `skip_mount` marker and removes the generated overlay directory. The current mounted font remains active until reboot; afterward the ROM files are visible again.

To uninstall, disable/remove the module and reboot. Persistent custom originals are intentionally retained for reinstall/update continuity; remove `/data/adb/persian_font_switcher` manually only if you also want to erase them.

## Build and validate

```sh
python3 -m pip install 'fonttools>=4.46,<5'
./scripts/build.sh
./scripts/validate.sh ./Persian-Font-Switcher-v0.1.0-rc3.zip
```

Validation covers every bundled font's hashes, metadata, weight strategy, shaping tables and visible Persian coverage; licenses and provenance; real WebUI previews; JavaScript SFNT/cmap rejection tests; switching every family; active-versus-pending hashes; System Default; FontLoader states; custom import/corruption/persistence; attack inputs; deterministic ZIP layout; and the rc2 KernelSU `0644` extraction regression.

The validated rc3 ZIP SHA-256 is:

```text
0de92ccbc00289aecdfcd58624f27a1288e033545f426815a7b037fac0afddfa
```

## Security and credits

See [SECURITY.md](SECURITY.md), [architecture](docs/ARCHITECTURE.md), [compatibility](docs/COMPATIBILITY.md), and [third-party notices](THIRD_PARTY_NOTICES.md).

Persian Font Switcher is authored and maintained by **Yasin Fadaee / [@ggYasin](https://github.com/ggYasin)**. The historical [`v33.003`](https://github.com/ggYasin/android-persian-font-switcher/releases/tag/v33.003), [`v0.1.0-rc1`](https://github.com/ggYasin/android-persian-font-switcher/releases/tag/v0.1.0-rc1), and [`v0.1.0-rc2`](https://github.com/ggYasin/android-persian-font-switcher/releases/tag/v0.1.0-rc2) releases remain preserved.
