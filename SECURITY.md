# Security policy

## Privileged WebUI boundary

KernelSU Next injects a JavaScript `ksu` bridge into the module WebUI. Its command methods execute as root in the global mount namespace. The WebUI is therefore privileged module code, not an ordinary untrusted webpage.

Persian Font Switcher uses asynchronous `ksu.exec` only for fixed scripts under `/data/adb/modules/persian_font_switcher/scripts/`. Before constructing a command, JavaScript requires:

- the exact module ID and module directory from `ksu.moduleInfo()`;
- an ID matching `^[a-z0-9][a-z0-9_-]{0,31}$`;
- exact membership in the bundled manifest or the validated custom-font registry.

The shell validates the ID again. Bundled IDs resolve only to canonical `assets/fonts/<id>/regular.ttf` and `bold.ttf`; custom IDs must equal their Regular/Bold content-addressed hashes under the fixed persistent store. Only the four hard-coded Android destinations are accepted. Font names, authors, descriptions, picker URIs, arbitrary paths, and arbitrary shell commands are never accepted as command input.

KernelSU Next's HTML file chooser returns only explicitly user-selected document URIs to the ordinary browser File API. Custom imports feature-detect `ksu.fileOutputStream()`, validate both files in JavaScript, create a random 32-character lowercase-hex token, and stream bytes only to `/data/adb/persian_font_switcher/staging/<token>/`. The trusted shell accepts only `begin`, `finish`, or `cancel` plus that strict token, then checks size, SFNT magic, metadata encoding, and content hashes before an atomic rename. The bridge API is implemented in KernelSU Next v3.1.0+ but is not currently documented in its published API document, so unsupported managers receive no import button.

The WebUI is self-contained, has a restrictive Content Security Policy, performs no external network request, contains no external navigation, and has no telemetry or analytics. Font source URLs in the manifest are documentation/provenance strings and are not fetched by the WebUI.

## System changes

The module has no Zygisk component, daemon, `service.sh`, `post-fs-data.sh`, SELinux policy, system property, font XML edit, app injection, or mount implementation. It never writes the physical system partition.

Font selection writes generated files only under the module's own `system/fonts` directory, mirrors selection under its own `state` directory, and uses KernelSU Next's official `ksud module config` facility when available. Custom originals and metadata live under the module-owned `/data/adb/persian_font_switcher` directory so KernelSU's whole-directory module replacement cannot erase them during an update. They are never exposed as arbitrary shell paths.

A compatible systemless mount provider is external to this module. The project does not install, configure, or change that provider, root hiding, app profiles, integrity attestation, NeoZygisk, Vector, LSPosed, TrickyStore, or related settings.

## Integrity and failure behavior

Bundled source hashes are pinned in the manifest and checked before copying. All four files are staged before the active module overlay directory is replaced. `skip_mount` is created before mutation and removed only after a complete successful font selection. An interrupted or failed selection therefore favors ROM defaults rather than a partial Regular/Bold overlay.

System Default deliberately retains `skip_mount` and removes generated overlay files. It does not copy ROM fonts into writable storage.

Active state hashes all four effective font targets from PID 1's mount namespace when `nsenter` is available. No bundled/custom font is reported active unless both Regular targets and both Bold targets match the same trusted hash pair. Unmatched state is reported as System Default or unrecognized rather than guessed.

The WebUI's Reboot button invokes only the fixed `reboot-device.sh` after an explicit confirmation. There is no arbitrary restart argument, live remount, SystemUI kill, zygote control, or automatic reboot.

## Reporting

Verify release SHA-256 values before installation. Report suspected vulnerabilities privately through this repository's GitHub Security Advisories rather than publishing exploitable details in an issue.
