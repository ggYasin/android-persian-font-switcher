# Vazirmatn Persian Fallback

A minimal KernelSU Next / Magisk-style module for Android 16 that overlays
Android's Arabic-script fallback fonts with Vazirmatn UI Non-Latin. Because
these font builds contain no Latin letters, the selected crDroid/Android Latin
`sans-serif` font remains in use for English text.

The module has no daemon, boot scripts, Zygisk component, SELinux policy,
system properties, font XML changes, or mount implementation. It relies on an
already-active systemless mount provider such as Magic Mount-rs and does not
read or change its configuration.

## Overlaid Android files

| Android path | Embedded source |
| --- | --- |
| `/system/fonts/NotoNaskhArabicUI-Regular.ttf` | `Vazirmatn-UI-NL-Regular.ttf` |
| `/system/fonts/NotoNaskhArabicUI-Bold.ttf` | `Vazirmatn-UI-NL-Bold.ttf` |
| `/system/fonts/NotoNaskhArabic-Regular.ttf` | `Vazirmatn-UI-NL-Regular.ttf` |
| `/system/fonts/NotoNaskhArabic-Bold.ttf` | `Vazirmatn-UI-NL-Bold.ttf` |

This covers Android's compact/UI and elegant Arabic-script fallbacks. It can
affect Persian, Arabic, Urdu, and other text using the same Arabic-script
fallback—not Persian alone. Apps or web pages that explicitly bundle their own
font may remain unchanged.

## Source and checksums

The fonts are the official **Vazirmatn v33.003 UI Non-Latin** TTF builds from
the [Vazirmatn repository](https://github.com/rastikerdar/vazirmatn) and
[v33.003 release](https://github.com/rastikerdar/vazirmatn/releases/tag/v33.003).

| File | SHA-256 |
| --- | --- |
| `Vazirmatn-UI-NL-Regular.ttf` | `99e8e85dc30507c90562c2967f1f2c29b64d45763d3807abe30fadf451bd64fc` |
| `Vazirmatn-UI-NL-Bold.ttf` | `f93fe4bcf136cd1131a475813e0916657055ba745f66d28cff091016bb2e4454` |
| `system/fonts/NotoNaskhArabicUI-Regular.ttf` | `99e8e85dc30507c90562c2967f1f2c29b64d45763d3807abe30fadf451bd64fc` |
| `system/fonts/NotoNaskhArabic-Regular.ttf` | `99e8e85dc30507c90562c2967f1f2c29b64d45763d3807abe30fadf451bd64fc` |
| `system/fonts/NotoNaskhArabicUI-Bold.ttf` | `f93fe4bcf136cd1131a475813e0916657055ba745f66d28cff091016bb2e4454` |
| `system/fonts/NotoNaskhArabic-Bold.ttf` | `f93fe4bcf136cd1131a475813e0916657055ba745f66d28cff091016bb2e4454` |
| `Vazirmatn-Persian-Fallback-v33.003.zip` | `46e83e66f97e37c256474d99f14814f412fdbb1bcedda832097b2017fb098784` |

The font files are redistributed under the SIL Open Font License 1.1; see
[`LICENSES/OFL-1.1.txt`](LICENSES/OFL-1.1.txt). Module scripts and documentation
are MIT licensed.

## Install

1. Confirm Magic Mount-rs is installed and active.
2. Open KernelSU Next → Modules → Install from storage.
3. Select `Vazirmatn-Persian-Fallback-v33.003.zip`.
4. Reboot.

The installer intentionally supports Android 16 / API 36 only and aborts if
the four expected ROM font paths are absent. It writes only into its module
directory during installation and never modifies the physical `/system`
partition.

## Uninstall

Disable or remove the module in KernelSU Next, then reboot.

## Build and validate

On Linux with `zip`, `unzip`, `sha256sum`, and `file` available:

```sh
./scripts/build.sh
./scripts/validate.sh ./Vazirmatn-Persian-Fallback-v33.003.zip
```

See [compatibility notes](docs/COMPATIBILITY.md) before adapting this module to
another Android version or ROM.

## Credits

- Packaged and maintained by **Yasin Fadaee** ([@ggYasin](https://github.com/ggYasin)).
- Vazirmatn was created by **Saber Rastikerdar** and its contributors.
