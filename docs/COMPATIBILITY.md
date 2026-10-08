# Compatibility

## Android layout

Version 0.2.0-rc1 supports Android 12–16 / API 31–36 only when the ROM uses the complete AOSP Arabic fallback layout. See [Requirements](REQUIREMENTS.md) for the normative support policy and tested-device matrix.

| Variant | Weight | Filename |
| --- | ---: | --- |
| compact/UI | 400 | `NotoNaskhArabicUI-Regular.ttf` |
| compact/UI | 700 | `NotoNaskhArabicUI-Bold.ttf` |
| elegant | 400 | `NotoNaskhArabic-Regular.ttf` |
| elegant | 700 | `NotoNaskhArabic-Bold.ttf` |

The same `und-Arab` mapping appears in AOSP's tagged font configuration for [Android 12](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-12.0.0_r1/data/fonts/fonts.xml), [12L](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-12.1.0_r1/data/fonts/fonts.xml), [13](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-13.0.0_r1/data/fonts/fonts.xml), [14](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-14.0.0_r1/data/fonts/fonts.xml), [15](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-15.0.0_r1/data/fonts/fonts.xml), and [16](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-16.0.0_r1/data/fonts/fonts.xml).

Installation requires all of the following:

1. API 31–36.
2. A readable `/system/etc/fonts.xml`.
3. The required unnamed `und-Arab` families in that base configuration.
4. All four exact names referenced by that configuration.
5. All four corresponding files under `/system/fonts`.

The installer rejects partial layouts. It does not infer support from Android version alone and does not claim generic Samsung, Xiaomi, or other vendor-ROM compatibility.

The working baseline is crDroid 12 / Android 16 on POCO X3 Pro (`vayu`) with KernelSU Next Manager 3.3.0 and Magic Mount-rs. The exact KernelSU kernel/userspace and Magic Mount-rs versions were not recorded for that rc4 test and are therefore documented as unknown rather than inferred. Version 0.2.0-rc1 retains rc4's four-target layout and the rc2 explicit-shell installer fix for KernelSU's `0644` extraction behavior. Its new transaction/custom-lifecycle changes remain prerelease until an update-from-rc4 smoke test is completed on that device.

## Root manager and WebUI

The WebUI is built against KernelSU Next Manager v3.3.0 (33214) and requires a working KernelSU Next installation; installing the Manager app alone is not a root environment. KernelSU Next v3.0.0 or newer supports the module-config backend. Custom imports require v3.1.0+ and feature-detect its implemented `ksu.fileOutputStream()` bridge; bundled selection remains available without that optional bridge.

The ZIP follows Magisk-style module structure. Magisk can provide the static systemless overlay, but Magisk Manager itself does not provide this KernelSU WebUI. Other WebUI hosts are untested and should not be assumed compatible.

## Mount providers and root hiding

Since 0.3.0 the module ships no `system/` payload, so no metamodule mounts anything for it. Magic Mount-rs or another provider can stay installed for other modules; its `umount` setting does not affect this module.

Activation is a short-lived bind mount inside `system_server`'s own mount namespace only. It is created with `nsenter` after `system_server` has unshared from zygote, and it is removed as soon as FontManagerService has built its font map, before apps start. NeoZygisk moves apps it does not hide into a copy of `system_server`'s live namespace, so a persistent bind would reach them; the transient one does not. KernelSU's per-app "umount modules" profiles, NeoZygisk's denylist, and SUSFS settings can stay as they are. The module uses no Zygisk component and no SUSFS feature.

Apps that render Persian map the selected font from `/data/fonts/persian_font_switcher/gen/<N>/`, the same kind of `/data/fonts` path Android's updatable fonts use. Apps that parse `/system/etc/fonts.xml` themselves (for example Flutter) see the stock file and keep the stock fallback.

## Restart behavior

A reboot is the recommended apply path. Apply now rebuilds the font map with `cmd font restart` and restarts SystemUI and the launcher; other apps receive the new map when they next start. This is safe here because earlier font generations stay on disk until the next boot.

## FontLoader

FontLoader (module ID `fontloader`) is not needed. It replaces already-mapped fonts in app memory with `mmap(MAP_FIXED)` from an ashmem copy sized to the module font; when the app had mapped the larger stock font, the kernel rejects the mapping after the old one was already removed, and the first Persian glyph crashes the app. The WebUI reports its state and recommends removal; this module never installs, enables, disables, or configures it.

## App behavior

The target is the shared Arabic-script fallback rather than Persian alone. Persian, Arabic, Urdu, and other Arabic-script languages can change. An app that explicitly bundles and chooses its own font, a downloadable web font, a canvas renderer, or a game engine can bypass the system fallback.
