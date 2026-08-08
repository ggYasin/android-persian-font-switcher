# Architecture

## WebUI API

KernelSU Next serves `webroot/index.html` from the module directory and exposes the `ksu` JavaScript bridge. This project depends on:

- `ksu.moduleInfo()` for the trusted module ID and directory check;
- asynchronous `ksu.exec(command, optionsJson, callbackName)` for exit code, stdout, and stderr;
- `ksu.fileOutputStream()` for feature-detected, fixed-path binary custom-font transfer on Manager v3.1.0+;
- `ksu.toast()` for an optional success notification.

The implementation was checked against [KernelSU Next v3.3.0 API documentation](https://github.com/KernelSU-Next/KernelSU-Next/blob/v3.3.0/docs/WebUi_Next/API_DOC.md), its [bridge implementation](https://github.com/KernelSU-Next/KernelSU-Next/blob/v3.3.0/manager/app/src/main/java/com/rifsxd/ksunext/ui/webui/WebViewInterface.kt), and its [Android file chooser](https://github.com/KernelSU-Next/KernelSU-Next/blob/v3.3.0/manager/app/src/main/java/com/rifsxd/ksunext/ui/webui/WebUIActivity.kt#L196-L228). The binary stream is implemented in current manager source but omitted from the published API document, so it is feature-detected. The project does not use `ksu.spawn`, because that API's current implementation concatenates arguments into a shell command. No dedicated reboot bridge exists; the confirmed Reboot action calls one fixed module-local script.

The WebUI fetches only its local `font-manifest.json`, loads candidate preview files from `webroot/fonts` or validated `webroot/custom-fonts` copies, and calls fixed allowlisted scripts. It has no external resources. Standard HTML file inputs are handled by KernelSU Next's Android document picker; selected bytes are read through the browser File API.

## Selection flow

```text
manifest/custom-registry card selection
    → JavaScript syntax + membership validation
    → scripts/apply-font.sh <id>
    → shell syntax + bundled/custom membership validation
    → validate source paths and SHA-256
    → create skip_mount fail-safe
    → stage all four Regular/Bold destinations
    → swap the module's system/fonts directory
    → persist selected_font
    → remove skip_mount only for a complete font overlay
    → compare effective mounted hashes with pending selection
    → report reboot required
```

The official KernelSU Next store is invoked as:

```sh
KSU_MODULE=persian_font_switcher /data/adb/ksu/bin/ksud module config set selected_font <allowlisted-id>
```

The module-local `state/selected-font` mirror supports status recovery if the config CLI is unavailable. Restart-required state is not a saved Boolean; it is recomputed by comparing the selected ID with effective mounted hashes.

rc4 also derives restart state from reality: `get-status.sh` hashes both compact/elegant Regular and Bold targets in PID 1's mount namespace when possible, and matches the complete pair against bundled and persistent custom hashes. Saved selection is reported separately. Unknown effective hashes are never labeled as a known font.

## Custom import flow

```text
user selects Regular + Bold through Android picker
    → browser validates size, SFNT bounds, required tables, weight, and visible Persian cmap coverage
    → random 128-bit lowercase-hex token
    → trusted begin script creates only fixed persistent staging/token paths
    → ksu.fileOutputStream writes bytes without shell arguments
    → trusted finish script validates token/path/size/magic/name/hashes
    → content-addressed custom ID
    → atomic rename into /data/adb/persian_font_switcher/custom-fonts
    → rebuild read-only module-local WebUI preview copies
```

KernelSU replaces the entire module directory on update. The separate module-owned persistent directory is therefore necessary for imported binaries; `customize.sh` recreates preview copies after each update. Preview recovery is optional and non-fatal: no registry is a no-op, valid entries are copied, and invalid/unreadable entries remain untouched while a private quarantine diagnostic is written when possible. A stale synchronization lock is preserved under quarantine and repaired; a lock owned by a live process defers recovery instead of blocking installation, and the WebUI retries later. No chosen filename or display name is used as a path or shell argument.

## Restart model

Applying changes only stages the next overlay atomically. Magic Mount-rs' live bind remains attached to the previous inode, and Android font maps are per-process/one-shot. rc4 intentionally provides Reboot now or Later, not SystemUI-only or zygote-only shortcuts. It never refreshes mounts itself or edits an external mount provider.

## System Default

System Default creates `skip_mount`, replaces the active selection with `system-default`, and removes the generated `system/fonts` directory. The WebUI and font assets remain available. After reboot, the mount provider skips this module and Android sees its original files.

## Adding layouts

Do not add filenames based only on a device marketing name or Android version. A new layout requires evidence of the active XML mapping, exact files, complete weight/variant semantics, capability checks in `customize.sh`, allowlisting in `scripts/lib.sh`, apply tests, and compatibility documentation.
