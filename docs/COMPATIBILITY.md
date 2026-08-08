# Compatibility and design

This release is deliberately fail-closed for Android 16 / API 36. During
installation, `customize.sh` checks the API level and confirms all four target
files exist in the device's `/system/fonts` view before setting the packaged
font files to mode `0644`.

The module assumes the ROM's font configuration already maps the following
files as Arabic-script fallbacks:

- `NotoNaskhArabicUI-Regular.ttf`
- `NotoNaskhArabicUI-Bold.ttf`
- `NotoNaskhArabic-Regular.ttf`
- `NotoNaskhArabic-Bold.ttf`

Only those files are overlaid. There are no XML edits, so a ROM that uses
different filenames or maps different fonts must not bypass the installer
check without reviewing its actual font configuration.

The module supplies no mounting code. KernelSU Next users need a compatible,
active mount metamodule such as Magic Mount-rs. The module neither reads nor
changes `config.toml`, root hiding, integrity attestation, NeoZygisk, Vector, or
LSPosed settings.

Systemless overlays are reversible: disable or remove the module and reboot.
They do not rewrite the physical system partition. Nevertheless, keep a known
working way to disable modules if experimenting on an untested ROM.
