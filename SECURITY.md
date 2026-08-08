# Security policy

## Privileged WebUI boundary

KernelSU Next injects a JavaScript `ksu` bridge into the module WebUI. Its command methods execute as root in the global mount namespace. The WebUI is therefore privileged module code, not an ordinary untrusted webpage.

Persian Font Switcher uses the documented asynchronous `ksu.exec` API only for fixed scripts under `/data/adb/modules/persian_font_switcher/scripts/`. Before constructing a command, JavaScript requires:

- the exact module ID and module directory from `ksu.moduleInfo()`;
- an ID matching `^[a-z0-9][a-z0-9_-]{0,31}$`;
- exact membership in the bundled font manifest.

The shell validates the ID against the same manifest again. It permits only canonical `assets/fonts/<id>/regular.ttf` and `bold.ttf` paths and the four hard-coded Android destinations. Font names, authors, descriptions, URLs, arbitrary paths, and arbitrary shell commands are never accepted as input.

The WebUI is self-contained, has a restrictive Content Security Policy, performs no external network request, contains no external navigation, and has no telemetry or analytics. Font source URLs in the manifest are documentation/provenance strings and are not fetched by the WebUI.

## System changes

The module has no Zygisk component, daemon, `service.sh`, `post-fs-data.sh`, SELinux policy, system property, font XML edit, app injection, or mount implementation. It never writes the physical system partition.

Font selection writes generated files only under the module's own `system/fonts` directory, mirrors selection under its own `state` directory, and uses KernelSU Next's official `ksud module config` facility when available. That external configuration store is maintained by KernelSU and removed when the module is uninstalled.

A compatible systemless mount provider is external to this module. The project does not install, configure, or change that provider, root hiding, app profiles, integrity attestation, NeoZygisk, Vector, LSPosed, TrickyStore, or related settings.

## Integrity and failure behavior

Bundled source hashes are pinned in the manifest and checked before copying. All four files are staged before the active module overlay directory is replaced. `skip_mount` is created before mutation and removed only after a complete successful font selection. An interrupted or failed selection therefore favors ROM defaults rather than a partial Regular/Bold overlay.

System Default deliberately retains `skip_mount` and removes generated overlay files. It does not copy ROM fonts into writable storage.

## Reporting

Verify release SHA-256 values before installation. Report suspected vulnerabilities privately through this repository's GitHub Security Advisories rather than publishing exploitable details in an issue.
