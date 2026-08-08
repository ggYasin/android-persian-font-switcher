# Changelog

## 0.1.0-rc3

- Expanded the licensed bundled set from 3 to 13 families: Vazirmatn, Estedad, Sahel, Shabnam, Samim, Tanha, Gandom, Parastoo, Mikhak, Cairo, Noto Sans Arabic, Noto Kufi Arabic, and IBM Plex Sans Arabic.
- Added searchable real-font previews, active versus selected state, one Apply action, restart guidance, and FontLoader status.
- Added KernelSU Next file-picker custom Regular/Bold import with client-side SFNT/Persian/weight validation, trusted fixed-path streaming, content-addressed IDs, atomic persistence, and preview restoration across module updates.
- Derived active state from the four effective mounted font hashes rather than saved selection alone.
- Added an explicit confirmed Reboot action and retained Later; intentionally omitted misleading SystemUI/zygote-only refresh actions because they cannot refresh the pinned mount and every process font map safely.
- Added every-font, switching, active/pending, System Default, FontLoader, custom import/corruption/update-persistence, WebUI validator, attack-input, and existing rc2 `0644` installer regression tests.
- Documented IRANSans as excluded from public redistribution because the supplied upstream mirror requires separate FontIran rights; licensed users can import their own files locally.

## 0.1.0-rc2

- Fixed initial installation under KernelSU Next, which normalizes ordinary extracted payload files to mode `0644` before sourcing `customize.sh`.
- Made initial font preparation invoke `apply-font.sh` through an explicit shell, independent of ZIP executable-bit preservation.
- Normalized runtime script permissions explicitly to `0755` before initialization and reasserted them afterward for WebUI execution.
- Added installer output forwarding with the apply script's exit status, machine-readable error code, message, stdout, and stderr.
- Added an extracted-payload regression test that forces scripts to `0644`, runs the actual installer, verifies the four Vazirmatn mappings and final `0755` modes, and exercises detailed checksum-failure diagnostics.

## 0.1.0-rc1

- Renamed the project and module to Persian Font Switcher.
- Added the offline KernelSU Next WebUI and official module-config persistence.
- Added manifest-backed Vazirmatn, Estedad, Sahel, and System Default choices.
- Added fail-safe, checksum-validated Regular/Bold overlay generation.
- Added capability-based AOSP Android 12–16 layout checks and conflict detection.
- Added deterministic builds, font/WebUI security validation, and attack-input tests.

Device installation and WebUI execution still require explicit user testing, so the first multi-font publication is a release candidate rather than a stable release.

## Legacy v33.003

- Historical Vazirmatn-only static Arabic fallback module.
- Preserved at [release v33.003](https://github.com/ggYasin/android-persian-font-switcher/releases/tag/v33.003).
