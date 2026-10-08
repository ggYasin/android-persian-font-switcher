# Security policy

## Supported versions

| Version | Security support |
| --- | --- |
| 0.2.x prereleases | Supported |
| 0.1.0 release candidates | Upgrade required after 0.2.0-rc1 is published |
| Legacy v33.003 | Historical; no active fixes |

## Privileged WebUI boundary

KernelSU Next injects a JavaScript `ksu` bridge into the module WebUI. Its command methods execute as root in the global mount namespace. The WebUI is therefore privileged module code, not an ordinary untrusted webpage.

Persian Font Switcher uses the callback-form `ksu.exec` overload only for fixed scripts under `/data/adb/modules/persian_font_switcher/scripts/`. KernelSU Next executes the root command before it posts the JavaScript callback, so the WebUI callback watchdog can detect a missing callback after control returns but cannot interrupt a root command that is itself hung. Before constructing a command, JavaScript requires:

- the exact module ID and module directory from `ksu.moduleInfo()`;
- an ID matching `^[a-z0-9][a-z0-9_-]{0,31}$`;
- exact membership in the bundled manifest or the validated custom-font registry.

The shell validates the ID again. Bundled IDs resolve only to canonical `assets/fonts/<id>/regular.ttf` and `bold.ttf`; custom IDs must equal their Regular/Bold content-addressed hashes under the fixed persistent store. Only the four hard-coded Android destinations are accepted. Font names, authors, descriptions, picker URIs, arbitrary paths, and arbitrary shell commands are never accepted as command input.

KernelSU Next's HTML file chooser returns only explicitly user-selected document URIs to the ordinary browser File API. Custom imports feature-detect `ksu.fileOutputStream()`, validate both files structurally in JavaScript, require WebView's font parser to load the exact pair, repeat that gate immediately before transfer, create a random 32-character lowercase-hex token, and stream bytes only to `/data/adb/persian_font_switcher/staging/<token>/`. The trusted shell accepts only `begin`, `finish`, or `cancel` plus that strict token, then checks size, SFNT magic, metadata encoding, and content hashes before an atomic rename. The bridge API is implemented in KernelSU Next v3.1.0+ but is not currently documented in its published API document, so unsupported managers receive no import button.

The WebUI is self-contained, has a restrictive Content Security Policy, performs no external network request, contains no external navigation, and has no telemetry or analytics. Font source URLs in the manifest are documentation/provenance strings and are not fetched by the WebUI. KernelSU Manager may independently fetch the public `updateJson` metadata declared by the module; that is outside the WebUI/runtime boundary.

## System changes

The module has no Zygisk component, SELinux policy change, system property, app injection, or `system/` payload, and it never writes the physical system partition. Since 0.3.0, `post-fs-data.sh`, `service.sh`, and `boot-completed.sh` run a fixed boot sequence and a small resident watcher. The watcher's only privileged action is a bind mount of the module's patched copy of the ROM font XML inside `system_server`'s own mount namespace, after verifying that this namespace differs from init's and zygote's, and its removal once FontManagerService has built the font map. The bind exists only while the font service parses the XML (about 3 seconds at boot): NeoZygisk copies `system_server`'s live namespace into apps it does not hide, so the bind is never left in place. No mount is ever created in init, zygote, or app namespaces.

Font selection writes verified copies and patched XML only under `/data/fonts/persian_font_switcher` (mode 0711/0644/0640, owner system, label `font_data_file`). It never touches FontManagerService's `/data/fonts/files` or `/data/fonts/config`. It mirrors the selection under the module's own `state` directory, and uses KernelSU Next's official `ksud module config` facility when available. Custom originals and metadata live under the module-owned `/data/adb/persian_font_switcher` directory so KernelSU's whole-directory module replacement cannot erase them during an update. They are never exposed as arbitrary shell paths.

Custom deletion accepts only a validated content-addressed custom ID, participates in the same advisory mutation lock as apply and import commit, refuses the selected family, atomically removes the fixed persistent directory, and rebuilds previews. The WebUI additionally prevents removing a family that is verified as currently active until the user switches and reboots.

The project does not install, configure, or change any mount provider, root hiding, app profiles, SUSFS, integrity attestation, NeoZygisk, Vector, LSPosed, TrickyStore, or related settings, and it does not rely on any of them.

## Integrity and failure behavior

Bundled source hashes are pinned in the manifest and re-verified before every staging, including at each boot. A new generation is staged in a temporary directory, verified, and renamed into place. Running apps may lazily open the generation served at boot, so a generation is never rewritten and old generations are removed only at the next boot. The patched XML changes only the four Arabic file names. It is generated from the pristine ROM file into its own generation directory, checked so that every target occurs exactly as often as in the ROM, never bound if that check fails, and never modified once published. Only this module's binds, recognized by their source path, are ever unmounted; another module's mount on the same path is left alone. A boot guard disables activation after two boots that did not complete, or when `system_server` dies twice shortly after a bind. After boot, if the font service does not resolve the patched configuration, or if SystemUI did not receive it after a rebuild, the bind is removed and stock fonts are restored. A shared nonblocking `flock` serializes apply, live apply, import commit, and deletion; the kernel releases it when the owning process exits. The retained lock file is not itself evidence that an operation is live.

System Default binds nothing and removes the staged copies at the next boot. The module never copies ROM fonts into writable storage.

Active state comes from the redirect record verified for the running `system_server`, the font map SystemUI received while verification is pending, and the hashes of the staged generation. No bundled/custom font is reported active unless both Regular copies and both Bold copies match the same trusted hash pair. Anything unverified is reported as unknown rather than guessed.

The WebUI's Reboot button invokes only the fixed `reboot-device.sh` after an explicit confirmation. Apply now invokes only the fixed `live-apply.sh` after confirmation: it binds inside `system_server` only around `cmd font restart`, and restarts SystemUI and the default launcher. The boot-completed step does the same only to repair a late boot-time bind. There is no arbitrary restart argument, zygote control, or automatic reboot.

## Reporting

Verify release SHA-256 values before installation. Report suspected vulnerabilities through the repository's private **Security → Advisories → Report a vulnerability** form rather than publishing exploitable details in an issue. Include the affected version and a minimal reproduction; do not attach proprietary font files or secrets.
