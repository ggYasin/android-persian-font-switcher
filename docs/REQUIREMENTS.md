# Requirements and support policy

Persian Font Switcher deliberately supports a narrow, capability-checked Android font layout. A matching Android version alone is not enough.

## Required for the supported experience

| Requirement | Supported value | Why it is required |
| --- | --- | --- |
| Android | Android 12–16 / API 31–36 | These releases have the verified AOSP Arabic fallback layout targeted by this module. |
| Root/module host | A working KernelSU Next installation with Manager 3.0.0 or newer | Provides the kernel/userspace root environment, module installation, the offline WebUI bridge, and persistent module configuration. Installing the Manager app alone is not sufficient. |
| Android command set | Android userspace exposing Toybox-compatible `awk`, `base64`, fd-form nonblocking `flock`, `od`, `sha256sum`, and `sync` | Installer/runtime validation, hashing, advisory serialization, and transaction storage barriers depend on these applets. The installer checks them before making module state active. |
| Systemless mount | None | The module ships no `system/` payload; activation is a bind inside `system_server`'s private mount namespace only. A metamodule may stay installed for other modules. |
| Base font configuration | Readable `/system/etc/fonts.xml` with the exact unnamed `und-Arab` compact and elegant families described below | Prevents applying four filenames that are present but not actually the expected base fallback family. OEM/updatable overrides remain unsupported. |
| Target files | All four exact files present under `/system/fonts` | Partial Regular/Bold or compact/elegant overlays are rejected. |
| Conflicts | No enabled module overlaying the four Arabic files or the ROM font XML | A competing overlay changes the configuration this module patches. |
| Restart | A reboot (recommended) or Apply now after installation and every changed selection | FontManagerService builds the font map apps receive at boot; Apply now rebuilds it and restarts SystemUI and the launcher. |

The installer requires these mappings inside the relevant family blocks, including upright weight semantics:

| Family | Weight | File |
| --- | ---: | --- |
| `lang="und-Arab" variant="compact"` | 400 | `NotoNaskhArabicUI-Regular.ttf` |
| `lang="und-Arab" variant="compact"` | 700 | `NotoNaskhArabicUI-Bold.ttf` |
| `lang="und-Arab" variant="elegant"` | 400 | `NotoNaskhArabic-Regular.ttf` |
| `lang="und-Arab" variant="elegant"` | 700 | `NotoNaskhArabic-Bold.ttf` |

The check accepts harmless XML whitespace, attribute order, and single/double quote differences. It is intentionally not a general Android font-configuration parser. OEM customization files, updatable fonts under `/data/fonts`, and vendor-specific alias chains remain unverified unless a device is added to the tested matrix.

## Feature-specific requirements

| Feature | Additional requirement |
| --- | --- |
| Bundled selection, status, System Default | KernelSU Next Manager 3.0.0+ and its callback-form WebUI `exec`/`moduleInfo` bridge |
| Custom Regular/Bold import | KernelSU Next Manager 3.1.0+ with `fileOutputStream()`, a current Android System WebView with Web Crypto/File/FontFace support, and exactly two structurally valid, WebView-renderable SFNT files no larger than 16 MiB each |
| Activation and active-font identification | `nsenter`, `mount`, `chcon`, `pidof`, `service`, `dumpsys`, and `cmd font` (all standard on Android 12+ with root) |
| Hidden apps | Nothing extra: apps open the font from `/data/fonts` without any mount. FontLoader is not needed and should be removed |
| In-manager update notices | Manager access to the public `updateJson` URL; the module WebUI and runtime scripts themselves make no network requests |

Custom fonts must contain Regular weight 250–550, Bold weight 600 or greater, required SFNT/shaping/name tables, Persian letters and digits, and must be legally usable by the device owner. Variable collections, TTC files, and WOFF/WOFF2 are not accepted.

## Storage and operational preparation

- Keep at least 32 MiB free for a normal install/update so the manager can retain the old module while preparing the new one.
- A maximum-size custom pair is 32 MiB. Import, persistent storage, and preview staging can temporarily require roughly three copies; keep about 128 MiB free before importing maximum-size files.
- Know how to disable or remove a KernelSU module before testing a prerelease. KernelSU modules are installed from the running Manager, not custom recovery.
- Back up custom font originals. Persistent copies normally survive module updates, but they are not a substitute for the user's licensed source files.
- Disable another font module and reboot before installing this one. Merely disabling a conflicting module without rebooting can leave its old mount active for the current boot.

## Explicitly unsupported or unverified

- Android API 30 and older, or API 37 and newer, until their mappings are reviewed and tested.
- ROMs without both exact `und-Arab` compact/elegant families, including many vendor-specific Samsung/Xiaomi layouts.
- OEM/updatable-font overrides that supersede the verified base `/system/etc/fonts.xml` mapping.
- Apps that parse `/system/etc/fonts.xml` themselves (for example Flutter) keep the stock fallback.
- Ordinary Magisk Manager as a host for this KernelSU-specific WebUI. A static Magisk-style overlay may mount, but that is not the supported interactive experience.
- Apps and web pages that explicitly bundle/select their own fonts.

## Tested-device matrix

| Device | ROM / API | Manager | Kernel/userspace | Mount provider | Provider version | Module result |
| --- | --- | --- | --- | --- | --- | --- |
| POCO X3 Pro (`vayu`) | crDroid 12 / Android 16 / API 36 | KernelSU Next 3.3.0 (33214) | Not recorded for the rc4 baseline | Magic Mount-rs | Not recorded for the rc4 baseline | rc4 installed and switching works; 0.2.0-rc1 retains the same four-target mount model and remains a prerelease pending update smoke testing |

The missing baseline versions are documented as unknown rather than guessed. Reports for this or other devices are welcome. Include the exact device codename, ROM build, API, KernelSU Next Manager and kernel/userspace versions, mount provider and version, FontLoader state, module version, installation log, and the WebUI's Active/Selected/ROM layout status. Do not attach proprietary font binaries or secrets.
