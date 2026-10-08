# Architecture

## WebUI API

KernelSU Next serves `webroot/index.html` from the module directory and exposes the `ksu` JavaScript bridge. This project depends on:

- `ksu.moduleInfo()` for the trusted module ID and directory check;
- callback-form `ksu.exec(command, optionsJson, callbackName)` for exit code, stdout, and stderr;
- `ksu.fileOutputStream()` for feature-detected, fixed-path binary custom-font transfer on Manager v3.1.0+;
- `ksu.toast()` for an optional success notification.

The implementation was checked against [KernelSU Next v3.3.0 API documentation](https://github.com/KernelSU-Next/KernelSU-Next/blob/v3.3.0/docs/WebUi_Next/API_DOC.md), its [bridge implementation](https://github.com/KernelSU-Next/KernelSU-Next/blob/v3.3.0/manager/app/src/main/java/com/rifsxd/ksunext/ui/webui/WebViewInterface.kt), and its [Android file chooser](https://github.com/KernelSU-Next/KernelSU-Next/blob/v3.3.0/manager/app/src/main/java/com/rifsxd/ksunext/ui/webui/WebUIActivity.kt#L196-L228). The binary stream is implemented in current manager source but omitted from the published API document, so it is feature-detected. The project does not use `ksu.spawn`, because that API's current implementation concatenates arguments into a shell command. No dedicated reboot bridge exists; the confirmed Reboot action calls one fixed module-local script.

The WebUI fetches only its local `font-manifest.json`, lazily loads candidate preview files from `webroot/fonts` or validated `webroot/custom-fonts` copies, and calls fixed allowlisted scripts. It has no external resources. Standard HTML file inputs are handled by KernelSU Next's Android document picker; selected bytes are read through the browser File API. Every privileged call has a bounded callback watchdog. The current Manager executes the root job synchronously before posting that callback, so the watchdog detects missing/late callbacks after control returns but cannot interrupt a root command that is itself hung. After an apply callback error or unknown outcome, the UI rereads authoritative status rather than assuming failure or success.

## Selection flow

```text
manifest/custom-registry card selection
    → JavaScript syntax + membership validation
    → scripts/apply-font.sh <id>
    → shell syntax + bundled/custom membership validation
    → validate source paths and SHA-256
    → stage a new /data/fonts/persian_font_switcher/gen/<N>/ with the four
      stock-named copies (0644, system:system, font_data_file), or reuse the
      current generation when it already holds this font
    → build xml/<N>/ with patched copies of the ROM font XML pointing at
      gen/<N> (staged, verified, renamed into place, then never modified)
    → publish <N> as the current generation only after both verified
    → persist selected_font and clear the boot guard
    → report reboot (or Apply now) required
```

The official KernelSU Next store is invoked as:

```sh
KSU_MODULE=persian_font_switcher /data/adb/ksu/bin/ksud module config set selected_font <allowlisted-id>
```

The module-local `state/selected-font` mirror supports status recovery if the config CLI is unavailable. Restart-required state is not a saved Boolean; it is recomputed by comparing the selected ID with effective mounted hashes.

The current release also derives restart state from reality: `get-status.sh` hashes both compact/elegant Regular and Bold targets in PID 1's mount namespace when possible, and matches the complete pair against bundled and persistent custom hashes. Saved selection is reported separately. Unknown effective hashes are never labeled as a known font.

Apply, custom-import commit, and custom deletion share one retained regular-file advisory lock. Toybox `flock` supplies nonblocking ownership, and the kernel releases that ownership on every process exit; the retained file alone never means an operation is live. Dead owner-identified directory locks left by prerelease builds are migrated conservatively. Fixed transaction metadata, storage barriers, and backup directories let a later apply verify or restore an overlay interrupted by a signal, process death, or sudden restart; a live lock owner remains a hard busy result.

## Custom import flow

```text
user selects Regular + Bold through Android picker
    → browser validates size, SFNT bounds, required tables, weight, and visible Persian cmap coverage
    → WebView's font sanitizer successfully loads both exact File objects
    → random 128-bit lowercase-hex token
    → trusted begin script creates only fixed persistent staging/token paths
    → ksu.fileOutputStream writes bytes without shell arguments
    → trusted finish script validates token/path/size/magic/name/hashes
    → content-addressed custom ID
    → atomic rename into /data/adb/persian_font_switcher/custom-fonts
    → rebuild read-only module-local WebUI preview copies
```

Stages created by this release carry a creation lease, become stale after 24 hours, and are pruned when a later import begins. Reimporting the same content updates only its display name; valid content-addressed binaries are not replaced through a crash-sensitive backup window. Custom deletion accepts only a validated `custom-…` ID, refuses the selected family, atomically removes the persistent entry, and resynchronizes previews. The normal WebUI additionally requires users to switch away and reboot before deleting an active custom family.

KernelSU replaces the entire module directory on update. The separate module-owned persistent directory is therefore necessary for imported binaries; `customize.sh` recreates preview copies after each update. Preview recovery is optional and non-fatal: no registry is a no-op, valid entries are copied, and invalid/unreadable entries remain untouched while a private quarantine diagnostic is written when possible. Preview synchronization uses its own retained advisory `flock`; fixed stage/backup paths bound crash residue and recover an interrupted preview swap. A live lock owner defers recovery instead of blocking installation, and the WebUI retries later. No chosen filename or display name is used as a path or shell argument.

## Activation model

```text
post-fs-data (before zygote)
    → System Default: remove /data/fonts/persian_font_switcher, stop
    → boot guard: skip if two previous activations never reached boot completion
    → re-verify the selected font and restage/reuse its generation
    → regenerate patched XML from the pristine ROM /system/etc/font_fallback.xml
      and fonts.xml; only the four Arabic file names change, to
      ../../data/fonts/persian_font_switcher/gen/<N>/<file>
    → delete unused generations, start the detached watcher
watcher (scripts/redirect-watcher.sh)
    → poll for system_server every 100 ms
    → require its mount namespace to differ from init's and zygote's
    → note whether the font binder service is already published
    → nsenter -t <system_server> -m mount -o bind xml/<N>/<xml> /system/etc/<xml>
      (on top of any other mount; this module's binds are recognized by their
      source root in mountinfo, and only those are ever unmounted)
    → wait for system_server's own copy of the finished font map, then
      unmount (the bind lives about 3 s, and is gone before apps start)
    → stay resident with a 2 s liveness check; rebind a restarted system_server
      the same way, and stop (tripping the boot guard) if it dies twice right
      after a bind
boot-completed (only once sys.boot_completed=1)
    → SystemUI's received font map contains gen/<N>: verified
    → map unreadable: trust system_server's own map, or else only a bind made
      while the font service was unpublished in a system_server at most 3 s old
    → otherwise: bind, `cmd font restart`, verify the dump, unbind, restart
      SystemUI and the launcher, confirm the new SystemUI received gen/<N>, or
      roll back to stock
    → make sure no bind is left, clear the boot guard
```

FontManagerService serializes font file paths into the shared font map, and libhwui opens each path lazily in the app's own mount namespace. The patched paths resolve to a real `font_data_file` directory that AOSP policy already lets every app domain read (`allow appdomain font_data_file:file r_file_perms`). Apps therefore need no mount. `system_server`'s mount namespace is a slave of init's (`master:1`), so a bind created there does not propagate.

The bind must still be short-lived. NeoZygisk caches `system_server`'s live mount namespace as its "root" namespace and moves every app it does not hide (root-granted apps, apps outside its denylist, and the WebView zygote) into it before that app unshares. On device, such apps copied a persistent bind. FontManagerService reads the XML only while it builds the map, so the watcher unmounts as soon as `system_server` has mapped the finished map. Every rebuild (`cmd font restart` is synchronous) is likewise bracketed by bind and unbind. A scan of every process after boot finds no copy. The module never writes `/data/fonts/files` or `/data/fonts/config`, which FontManagerService manages and validates, and it never ships a `system/` payload for a metamodule to mount.

`dumpsys font` re-parses the XML that `system_server` currently sees, so it is checked only while bound: it proves the patched configuration parses and resolves, but not which map was served. After the unbind it shows the stock paths again. The served map is checked directly instead: SystemUI keeps the shared-memory font map it received from FontManagerService mapped for its lifetime, and root can read it through `/proc/<pid>/map_files`. The map contains the font paths, so finding `gen/<N>/` there proves apps received the redirect.

Apply now (`scripts/live-apply.sh`) binds the new generation, restarts the font service, verifies the dump, unbinds, restarts SystemUI and the launcher, and confirms the new SystemUI's map. System Default only rebuilds the map without a bind. Boot-completed repair, the watcher's rebuild, Apply, and Apply now share the same operation lock. Generations are only garbage-collected at the next boot, so running apps that lazily open an older generation never lose it.

## Adding layouts

Do not add filenames based only on a device marketing name or Android version. A new layout requires evidence of the active XML mapping, exact files, complete weight/variant semantics, capability checks in `customize.sh`, allowlisting in `scripts/lib.sh`, apply tests, and compatibility documentation.
