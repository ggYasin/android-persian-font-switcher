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

## Mount providers

KernelSU configurations need a compatible provider for module `system/` overlays. The module contains no mount implementation and never installs or configures a provider.

Dynamic switching is designed for providers that inspect `/data/adb/modules/<id>/system` at boot. Current Magic Mount-rs follows this model and honors `skip_mount`, so it is a known compatible example.

Some overlayfs metamodules copy module payloads into a separate provider-owned content directory during installation. Editing the original module directory later may not update their effective overlay. This module does not write provider-owned paths, so post-install switching is not claimed for that design.

System Default uses KernelSU's standard `skip_mount` marker, which keeps the WebUI installed while telling compatible providers not to mount this module's `system/` payload.

The project does not store copies or trusted baselines of ROM fonts. Effective hashes that do not match a bundled/custom family are therefore reported as `unknown` (“System default or unrecognized”), even when System Default is selected. This avoids turning saved state into a false active-font claim.

## Runtime refresh

The module does not offer Restart SystemUI or soft Android restart. crDroid's current font picker [switches a preinstalled Runtime Resource Overlay and then calls its SystemUI restart helper](https://github.com/crdroidandroid/android_packages_apps_crDroidSettings/blob/07664c875678f548450f788f319044ee09174f5c/src/com/crdroid/settings/preferences/FontsPickerPreference.kt#L181-L227); its framework helper ultimately [asks `IStatusBarService` to restart SystemUI](https://github.com/crdroidandroid/android_frameworks_base/blob/708e793e39322960e8f61edf2028aa30b07901fe/core/java/com/android/internal/util/crdroid/Utils.java#L85-L91). crDroid's `FontController` then [selects a named family already present in the system font map](https://github.com/crdroidandroid/android_frameworks_base/blob/708e793e39322960e8f61edf2028aa30b07901fe/core/java/com/android/internal/util/android/FontController.java#L201-L229). That path is not a font-file refresh service.

[Current Magic Mount-rs instead bind-mounts each boot-time source](https://github.com/Tools-cx-app/meta-magic_mount-rs/blob/2e42e64f9d5054ec9f4ac313a931d331643a5ab8/src/magic_mount/mod.rs#L91-L135) and exposes no supported module-specific live-remount command. Replacing this module's source directory cannot retarget the existing bind to the new inode. Android's [`Typeface` system font map is one-shot within a process](https://android.googlesource.com/platform/frameworks/base/+/android16-release/graphics/java/android/graphics/Typeface.java#1537), [`SystemFonts` mmap font files](https://android.googlesource.com/platform/frameworks/base/+/android16-release/graphics/java/android/graphics/fonts/SystemFonts.java#118), and zygote can prewarm path-keyed font data for the current locale. Restarting SystemUI would therefore leave the new four-file overlay pending and cannot refresh existing apps. A zygote restart is disruptive and still does not replace the pinned mount. Android's own `cmd font restart` implementation [labels itself unsafe and intended only for testing](https://github.com/crdroidandroid/android_frameworks_base/blob/708e793e39322960e8f61edf2028aa30b07901fe/services/core/java/com/android/server/graphics/fonts/FontManagerShellCommand.java#L118-L122). A normal reboot is the only supported provider-agnostic apply path.

## FontLoader

The external FontLoader module uses ID `fontloader`. The WebUI reports enabled, disabled, pending install/removal, or not detected by inspecting standard module markers. It does not install or change FontLoader. Individual app mount namespaces can still differ from the PID 1/global active state, which is exactly the Android 12+ lazy-loading case FontLoader is designed to mitigate.

## App behavior

The target is the shared Arabic-script fallback rather than Persian alone. Persian, Arabic, Urdu, and other Arabic-script languages can change. An app that explicitly bundles and chooses its own font, a downloadable web font, a canvas renderer, or a game engine can bypass the system fallback.
