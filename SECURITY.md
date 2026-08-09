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

The module has no Zygisk component, daemon, `service.sh`, `post-fs-data.sh`, SELinux policy, system property, font XML edit, app injection, or mount implementation. It never writes the physical system partition.

Font selection writes generated files only under the module's own `system/fonts` directory, mirrors selection under its own `state` directory, and uses KernelSU Next's official `ksud module config` facility when available. Custom originals and metadata live under the module-owned `/data/adb/persian_font_switcher` directory so KernelSU's whole-directory module replacement cannot erase them during an update. They are never exposed as arbitrary shell paths.

Custom deletion accepts only a validated content-addressed custom ID, participates in the same advisory mutation lock as apply and import commit, refuses the selected family, atomically removes the fixed persistent directory, and rebuilds previews. The WebUI additionally prevents removing a family that is verified as currently active until the user switches and reboots.

A compatible systemless mount provider is external to this module. The project does not install, configure, or change that provider, root hiding, app profiles, integrity attestation, NeoZygisk, Vector, LSPosed, TrickyStore, or related settings.

## Integrity and failure behavior

Bundled source hashes are pinned in the manifest and checked before copying. All four files are staged before `skip_mount` or the active module overlay is touched. The transaction then records the prior state, creates `skip_mount`, and replaces the overlay. `skip_mount` is removed only after a complete successful font selection. A shared nonblocking `flock` serializes apply, import commit, and deletion; the kernel releases it when the owning process exits, while durable transaction markers let a later operation recover an interrupted overlay without accepting a partial Regular/Bold family. The retained lock file is not itself evidence that an operation is live.

System Default deliberately retains `skip_mount` and removes generated overlay files. It does not copy ROM fonts into writable storage.

Active state hashes all four effective font targets from PID 1's mount namespace when `nsenter` is available. No bundled/custom font is reported active unless both Regular targets and both Bold targets match the same trusted hash pair. Unmatched state is reported as System Default or unrecognized rather than guessed.

The WebUI's Reboot button invokes only the fixed `reboot-device.sh` after an explicit confirmation. There is no arbitrary restart argument, live remount, SystemUI kill, zygote control, or automatic reboot.

## Reporting

Verify release SHA-256 values before installation. Report suspected vulnerabilities through the repository's private **Security → Advisories → Report a vulnerability** form rather than publishing exploitable details in an issue. Include the affected version and a minimal reproduction; do not attach proprietary font files or secrets.
