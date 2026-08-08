# Compatibility

## Android layout

Version 0.1.0-rc1 supports Android 12–16 / API 31–36 only when the ROM uses the complete AOSP Arabic fallback layout:

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
3. An `und-Arab` family in that active configuration.
4. All four exact names referenced by that configuration.
5. All four corresponding files under `/system/fonts`.

The installer rejects partial layouts. It does not infer support from Android version alone and does not claim generic Samsung, Xiaomi, or other vendor-ROM compatibility.

The target is crDroid 12 / Android 16 on vayu. No device installation was performed while developing 0.1.0-rc1.

## Root manager and WebUI

The WebUI is built against the official KernelSU Next WebUI-Next API and was audited against Manager v3.3.0 (33214). KernelSU Next v3.0.0 or newer is the supported minimum for the official persistent module-config backend.

The ZIP follows Magisk-style module structure. Magisk can provide the static systemless overlay, but Magisk Manager itself does not provide this KernelSU WebUI. Other WebUI hosts are untested and should not be assumed compatible.

## Mount providers

KernelSU configurations need a compatible provider for module `system/` overlays. The module contains no mount implementation and never installs or configures a provider.

Dynamic switching is designed for providers that inspect `/data/adb/modules/<id>/system` at boot. Current Magic Mount-rs follows this model and honors `skip_mount`, so it is a known compatible example.

Some overlayfs metamodules copy module payloads into a separate provider-owned content directory during installation. Editing the original module directory later may not update their effective overlay. Version 0.1.0-rc1 does not write provider-owned paths, so post-install switching is not claimed for that design.

System Default uses KernelSU's standard `skip_mount` marker, which keeps the WebUI installed while telling compatible providers not to mount this module's `system/` payload.

## App behavior

The target is the shared Arabic-script fallback rather than Persian alone. Persian, Arabic, Urdu, and other Arabic-script languages can change. An app that explicitly bundles and chooses its own font, a downloadable web font, a canvas renderer, or a game engine can bypass the system fallback.
