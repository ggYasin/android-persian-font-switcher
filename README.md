# Persian Font Switcher

[![Validate module](https://github.com/ggYasin/android-persian-font-switcher/actions/workflows/validate.yml/badge.svg)](https://github.com/ggYasin/android-persian-font-switcher/actions/workflows/validate.yml)

An open-source KernelSU Next module with an offline WebUI for choosing Android's Persian/Arabic-script fallback font while preserving the selected Latin `sans-serif` family.

The module changes only the four known AOSP compact/elegant Arabic fallback entries. Since 0.3.0 it ships **no `system/` overlay and creates no mount in any app or zygote namespace**: the change is made only inside `system_server`, so it keeps working for apps that KernelSU/NeoZygisk hide module mounts from, and it does not weaken that hiding. It has no Zygisk component, font hook, runtime/WebUI network access, telemetry, or physical `/system` write. A small boot-time watcher performs the redirect. KernelSU Manager may separately fetch the public update metadata declared in `module.prop`.

## WebUI

- Searchable list with real embedded Regular/Bold Persian previews.
- Separate **Active in apps** state, **Selected** state, activation status, and restart-required status.
- One explicit Apply button, System Default, Reboot now, an optional **Apply now** (restarts SystemUI and the launcher), and Later.
- Manual status refresh, privileged-callback watchdogs, abandoned-operation recovery, and truthful outcome verification.
- FontLoader detection with a removal recommendation (it is not needed and can crash apps).
- Custom Regular+Bold import through KernelSU Next's Android file picker and root-backed binary stream.
- Safe custom-font removal after switching away and rebooting.
- Keyboard-accessible radio navigation and lazy preview loading for large custom collections.
- Local SFNT structure, shaping-table, weight, size, visible Persian glyph, and WebView renderability validation before import.

The active font is what Android's font service served to apps this boot. It comes from the redirect record verified for the running `system_server`, its live mount table, and the SHA-256 hashes of the staged copies. It is never inferred from saved configuration alone.

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

## How activation works

On Android 12+ apps do not read `fonts.xml` to build their system font map. `system_server`'s FontManagerService parses the ROM's `/system/etc/font_fallback.xml` (and legacy `fonts.xml`), serializes the resulting font **file paths** into shared memory, and every app opens those paths lazily in its own mount namespace. That is why a mount-based font module stops working for apps whose module mounts are hidden: the app resolves the path to the stock file.

Persian Font Switcher therefore:

1. copies the selected Regular/Bold files to `/data/fonts/persian_font_switcher/gen/<N>/` under the stock file names, labeled `font_data_file` (the same label and access rules Android's own updatable fonts use, readable by every app domain);
2. generates patched copies of the ROM's own font XML files at every boot, changing only the four Arabic fallback file names to `../../data/fonts/persian_font_switcher/gen/<N>/…`;
3. at boot, waits for `system_server` to unshare its mount namespace and bind-mounts the patched XML there, before FontManagerService starts, then removes the bind again as soon as the font map is built (about 3 seconds). The bind never exists in init or zygote, and it is gone before apps start, so no app can copy it;
4. after boot, verifies that the font map SystemUI received contains the selected generation. If the early bind was late, it rebuilds the font map once and restarts SystemUI and the launcher. If the configuration does not resolve, it restores stock fonts.

Apps then open the selected font from a normal `/data/fonts` path. Nothing is mounted in their namespace, so KernelSU/NeoZygisk unmount settings neither break the font nor need to be relaxed. A boot guard skips activation after two boots that did not complete, until a font is applied again.

Known limits:

- Apps that parse `/system/etc/fonts.xml` themselves (for example Flutter's Skia font manager and some game engines) see the stock file and keep the stock Arabic fallback.
- Apps that render Persian map the selected file from `/data/fonts/persian_font_switcher/…`, the same kind of path as Google's updatable fonts.

## Applying a selection

Apply stages a new generation and saves the selection. **Reboot now** is the recommended way to activate it: the redirect is in place before any app starts. **Apply now** activates it immediately: it binds inside `system_server` just long enough to rebuild the font map, and restarts SystemUI and the launcher. Apps that were already open show the new font after they are reopened. Earlier generations are kept until the next boot, because running apps may still lazily open them.

## FontLoader

[FontLoader](https://github.com/KernelSU-Modules-Repo/fontloader) is **not needed** and is not recommended alongside this module. It swaps already-mapped stock fonts in memory with `MAP_FIXED`, and that crashes apps with `SIGSEGV` when the replacement is smaller than the stock font. The WebUI detects module ID `fontloader` and recommends removing it. Persian Font Switcher never installs, enables, disables, or configures it.

## Requirements

The supported experience requires all of the following:

- Android 12–16 / API 31–36.
- A working KernelSU Next installation with Manager 3.0.0+; installing the Manager app alone is not sufficient. Custom import requires Manager 3.1.0+ and a current Android System WebView.
- The exact unnamed AOSP `und-Arab` compact/elegant families with Regular 400 and Bold 700 mappings to all four target files.
- No mount provider is required. A metamodule such as Magic Mount-rs may stay installed for other modules; this module ships nothing for it to mount.
- No other enabled module overlaying/replacing the Arabic fallback files or font XML, and a reboot (or Apply now) after install or selection changes.

See the complete [requirements and support policy](docs/REQUIREMENTS.md) for feature requirements, unsupported configurations, storage guidance, recovery preparation, and the tested-device matrix. Vendor layouts, OEM/updatable-font overrides, and provider-owned copied overlays are not assumed compatible.

## Android targets

```text
/system/fonts/NotoNaskhArabicUI-Regular.ttf
/system/fonts/NotoNaskhArabicUI-Bold.ttf
/system/fonts/NotoNaskhArabic-Regular.ttf
/system/fonts/NotoNaskhArabic-Bold.ttf
```

These stock files are never modified or mounted over; the four entries pointing at them are redirected inside `system_server` only. Persian, Arabic, Urdu, and other languages sharing the Arabic-script fallback may all change. Apps or web content explicitly selecting a bundled font can bypass Android's fallback.

## Download, verify, and install

1. Disable/remove another module overlaying these targets, then reboot. Removing FontLoader is recommended.
2. Download `Persian-Font-Switcher-v0.3.0.zip` and its `.sha256` file from the [v0.3.0 release](https://github.com/ggYasin/android-persian-font-switcher/releases/tag/v0.3.0).
3. Keep your existing KernelSU app profiles, NeoZygisk denylist, and metamodule settings unchanged.
4. Verify the archive before installing:

   ```sh
   sha256sum -c Persian-Font-Switcher-v0.3.0.zip.sha256
   ```

5. Install the ZIP from the running KernelSU Next Manager. Do not flash it from custom recovery.
6. Reboot, open the module WebUI, search/preview, choose a font, and tap Apply selection.
7. Reboot now (recommended), use Apply now, or reboot later.

System Default stops the redirect. After a reboot, or Apply now, the ROM's stock configuration is served and the staged copies are removed at the next boot.

To uninstall, disable/remove the module and reboot; `uninstall.sh` removes `/data/fonts/persian_font_switcher`. Persistent custom originals are intentionally retained for reinstall/update continuity; remove individual unselected fonts through the WebUI. Remove `/data/adb/persian_font_switcher` manually only if you also want to erase all retained custom data.

## Build and validate

The supported validation host is Linux with a POSIX shell, Python 3.10+, Node.js 20+, Info-ZIP `zip`, GNU `sha256sum`/`stat`, util-linux `flock`, and the exactly pinned FontTools dependency.

```sh
python3 -m pip install -r requirements-dev.txt
./scripts/build.sh
./scripts/validate.sh
```

Validation covers every bundled font's hashes, metadata, weight strategy, shaping tables and visible Persian coverage; licenses and provenance; real WebUI previews; JavaScript SFNT/cmap and renderability-gate rejection tests; switching every family into staged generations; byte-exact XML patching of both font XML formats; the system_server namespace guards, boot-time bind, late-bind repair, rollback, boot guard, and live apply; active-versus-pending state; System Default; FontLoader states; custom import/corruption/persistence; attack inputs; deterministic ZIP layout; and the rc2 KernelSU `0644` extraction regression.

Release CI publishes a matching `.sha256` file beside every validated module archive.

## Security and credits

See [SECURITY.md](SECURITY.md), [requirements](docs/REQUIREMENTS.md), [architecture](docs/ARCHITECTURE.md), [compatibility](docs/COMPATIBILITY.md), [contributing](CONTRIBUTING.md), and [third-party notices](THIRD_PARTY_NOTICES.md).

Persian Font Switcher is authored and maintained by **Yasin Fadaee / [@ggYasin](https://github.com/ggYasin)**. Historical releases remain preserved on the [Releases page](https://github.com/ggYasin/android-persian-font-switcher/releases).
