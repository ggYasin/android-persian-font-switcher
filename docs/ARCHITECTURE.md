# Architecture

## WebUI API

KernelSU Next serves `webroot/index.html` from the module directory and exposes the `ksu` JavaScript bridge. This project depends on:

- `ksu.moduleInfo()` for the trusted module ID and directory check;
- asynchronous `ksu.exec(command, callbackName)` for exit code, stdout, and stderr;
- `ksu.toast()` for an optional success notification.

The implementation was checked against [KernelSU Next v3.3.0 API documentation](https://github.com/KernelSU-Next/KernelSU-Next/blob/v3.3.0/docs/WebUi_Next/API_DOC.md) and its [bridge implementation](https://github.com/KernelSU-Next/KernelSU-Next/blob/v3.3.0/manager/app/src/main/java/com/rifsxd/ksunext/ui/webui/WebViewInterface.kt). It does not use `ksu.spawn`, because that API's current implementation concatenates arguments into a shell command. No dedicated reboot bridge exists.

The WebUI fetches only its local `font-manifest.json`, loads candidate preview files from `webroot/fonts`, and calls one of two fixed scripts. It has no external resources.

## Selection flow

```text
manifest-backed card selection
    → JavaScript syntax + membership validation
    → scripts/apply-font.sh <id>
    → shell syntax + manifest membership validation
    → validate source paths and SHA-256
    → create skip_mount fail-safe
    → stage all four Regular/Bold destinations
    → swap the module's system/fonts directory
    → persist selected_font
    → remove skip_mount only for a complete font overlay
    → report reboot required
```

The official KernelSU Next store is invoked as:

```sh
KSU_MODULE=persian_font_switcher /data/adb/ksu/bin/ksud module config set selected_font <allowlisted-id>
```

`reboot_required` is a temporary KernelSU config entry, so KernelSU clears it during the next boot. The module-local `state/selected-font` mirror supports status recovery if the config CLI is unavailable.

## System Default

System Default creates `skip_mount`, replaces the active selection with `system-default`, and removes the generated `system/fonts` directory. The WebUI and font assets remain available. After reboot, the mount provider skips this module and Android sees its original files.

## Adding layouts

Do not add filenames based only on a device marketing name or Android version. A new layout requires evidence of the active XML mapping, exact files, complete weight/variant semantics, capability checks in `customize.sh`, allowlisting in `scripts/lib.sh`, apply tests, and compatibility documentation.
