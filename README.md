# Persian Font Switcher

[![Validate module](https://github.com/ggYasin/android-persian-font-switcher/actions/workflows/validate.yml/badge.svg)](https://github.com/ggYasin/android-persian-font-switcher/actions/workflows/validate.yml)

An open-source KernelSU Next module with an offline WebUI for choosing Android's Persian/Arabic-script fallback font while preserving the selected Latin `sans-serif` family.

The module changes only the four known AOSP compact/elegant Arabic fallback paths. It has no daemon, service script, Zygisk component, font hook, runtime/WebUI network access, telemetry, or physical `/system` write. KernelSU Manager may separately fetch the public update metadata declared in `module.prop`.

## WebUI

- Searchable list with real embedded Regular/Bold Persian previews.
- Separate **Active** effective-mount state, **Selected** pending state, and restart-required status.
- One explicit Apply button, System Default, Reboot now, and Later.
- Manual status refresh, privileged-callback watchdogs, abandoned-operation recovery, and truthful outcome verification.
- FontLoader enabled/disabled/pending/not-detected status.
- Custom Regular+Bold import through KernelSU Next's Android file picker and root-backed binary stream.
- Safe custom-font removal after switching away and rebooting.
- Keyboard-accessible radio navigation and lazy preview loading for large custom collections.
- Local SFNT structure, shaping-table, weight, size, visible Persian glyph, and WebView renderability validation before import.

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

KernelSU Next Manager v3.1.0+ exposes the standard Android document picker and a binary file-output bridge. The module feature-detects that API, accepts exactly one Regular and one Bold file (maximum 16 MiB each), validates both structurally and through WebView's font parser, streams them to a random fixed staging location, and lets a trusted module script revalidate token, path, size, SFNT magic, and hashes.

Imported files are assigned a content-addressed `custom-…` ID and atomically persisted under:

```text
/data/adb/persian_font_switcher/custom-fonts/
```

That module-owned data directory survives KernelSU's whole-directory module update replacement. `customize.sh` rebuilds read-only WebUI preview copies on every update. Restoration is best-effort: absent data is a no-op, valid fonts are retained, the kernel releases advisory operation locks when a process exits, interrupted preview transactions are recovered, and malformed, actively locked, or unreadable entries cannot fail module installation. Skipped originals stay in place; diagnostic names are recorded privately in `/data/adb/persian_font_switcher/quarantine/skipped-custom-data.log` when writable. Abandoned import stages created by this release become eligible for cleanup after 24 hours and are pruned when another import begins. Display names and file-picker paths never enter a shell command. Custom files remain the user's licensing responsibility.

## Why restart is required

Applying a selection atomically prepares the module's next `system/fonts` overlay and saves the pending ID. It does not claim to change live processes.

Magic Mount-rs binds the current source object at boot. Replacing the module directory atomically does not retarget that live bind mount. Android also mmaps fonts and establishes process-local font maps/caches during initialization. Consequently:

- restarting only SystemUI still sees the provider's old boot-time bind, does not update existing apps, and may reuse zygote's path-keyed warm-up cache;
- a soft zygote restart without a supported provider remount still sees the old bind mount and is disruptive;
- the module does not perform ad-hoc runtime bind mounts or alter provider configuration.

crDroid's built-in font picker follows a different path: it [enables a preinstalled Runtime Resource Overlay](https://github.com/crdroidandroid/android_packages_apps_crDroidSettings/blob/07664c875678f548450f788f319044ee09174f5c/src/com/crdroid/settings/preferences/FontsPickerPreference.kt) and then [asks the status-bar service to restart SystemUI](https://github.com/crdroidandroid/android_frameworks_base/blob/708e793e39322960e8f61edf2028aa30b07901fe/core/java/com/android/internal/util/crdroid/Utils.java#L85-L91). It does not replace these four files or retarget the module's live mount, so copying that restart action would leave this module's new selection pending.

The honest provider-agnostic choices are **Reboot now** or **Later**. Rebooting reruns the external mount provider before zygote, SystemUI, apps, and FontLoader initialize.

## FontLoader

[FontLoader](https://github.com/KernelSU-Modules-Repo/fontloader) remains a separate optional Zygisk module. It can be important on Android 12+ when an app later loses access to module font paths through mount-namespace hiding while fonts are lazily loaded. The WebUI detects module ID `fontloader` and reports enabled, disabled, pending install/removal, or not detected. Persian Font Switcher never installs, enables, disables, or configures it.

## Requirements

The supported experience requires all of the following:

- Android 12–16 / API 31–36.
- A working KernelSU Next installation with Manager 3.0.0+; installing the Manager app alone is not sufficient. Custom import requires Manager 3.1.0+ and a current Android System WebView.
- The exact unnamed AOSP `und-Arab` compact/elegant families with Regular 400 and Bold 700 mappings to all four target files.
- A compatible systemless mount provider that rereads the module's `system/` tree at boot and honors `skip_mount`; Magic Mount-rs is the known-compatible example.
- No other enabled module overlaying/replacing the target paths, and a normal reboot after install or selection changes.

See the complete [requirements and support policy](docs/REQUIREMENTS.md) for feature requirements, unsupported configurations, storage guidance, recovery preparation, and the tested-device matrix. Vendor layouts, OEM/updatable-font overrides, and provider-owned copied overlays are not assumed compatible.

## Android targets

```text
/system/fonts/NotoNaskhArabicUI-Regular.ttf
/system/fonts/NotoNaskhArabicUI-Bold.ttf
/system/fonts/NotoNaskhArabic-Regular.ttf
/system/fonts/NotoNaskhArabic-Bold.ttf
```

Persian, Arabic, Urdu, and other languages sharing the Arabic-script fallback may all change. Apps or web content explicitly selecting a bundled font can bypass Android's fallback.

## Download, verify, and install

1. Disable/remove another module overlaying these targets, then reboot.
2. Confirm a compatible KernelSU systemless mount provider is active.
3. Download `Persian-Font-Switcher-v0.2.0-rc1.zip` and its `.sha256` file from the [v0.2.0-rc1 release](https://github.com/ggYasin/android-persian-font-switcher/releases/tag/v0.2.0-rc1).
4. Verify the archive before installing:

   ```sh
   sha256sum -c Persian-Font-Switcher-v0.2.0-rc1.zip.sha256
   ```

5. Install the ZIP from the running KernelSU Next Manager. Do not flash it from custom recovery.
6. Reboot, open the module WebUI, search/preview, choose a font, and tap Apply selection.
7. Reboot now or later when convenient.

System Default creates the standard `skip_mount` marker and removes the generated overlay directory. The current mounted font remains active until reboot; afterward the ROM files are visible again.

To uninstall, disable/remove the module and reboot. Persistent custom originals are intentionally retained for reinstall/update continuity; remove individual unselected fonts through the WebUI. Remove `/data/adb/persian_font_switcher` manually only if you also want to erase all retained custom data.

## Build and validate

The supported validation host is Linux with a POSIX shell, Python 3.10+, Node.js 20+, Info-ZIP `zip`, GNU `sha256sum`/`stat`, util-linux `flock`, and the exactly pinned FontTools dependency.

```sh
python3 -m pip install -r requirements-dev.txt
./scripts/build.sh
./scripts/validate.sh
```

Validation covers every bundled font's hashes, metadata, weight strategy, shaping tables and visible Persian coverage; licenses and provenance; real WebUI previews; JavaScript SFNT/cmap and renderability-gate rejection tests; switching every family; active-versus-pending hashes; System Default; FontLoader states; custom import/corruption/persistence; attack inputs; deterministic ZIP layout; and the rc2 KernelSU `0644` extraction regression.

Release CI publishes a matching `.sha256` file beside every validated module archive.

## Security and credits

See [SECURITY.md](SECURITY.md), [requirements](docs/REQUIREMENTS.md), [architecture](docs/ARCHITECTURE.md), [compatibility](docs/COMPATIBILITY.md), [contributing](CONTRIBUTING.md), and [third-party notices](THIRD_PARTY_NOTICES.md).

Persian Font Switcher is authored and maintained by **Yasin Fadaee / [@ggYasin](https://github.com/ggYasin)**. Historical releases remain preserved on the [Releases page](https://github.com/ggYasin/android-persian-font-switcher/releases).
