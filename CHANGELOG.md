# Changelog

## 0.2.0-rc1

- Preserved rc4's working four-target AOSP overlay, default Vazirmatn selection, mount-provider boundary, and reboot-only activation model.
- Strengthened installer requirements from unrelated whole-file string checks to exact `und-Arab` compact/elegant family membership, Regular/Bold weights, target presence, and atomic supported-target state.
- Fixed a shell conditional failure mode that could mask selection-state write errors; all critical state operations now return explicit status.
- Staged and verified complete font payloads before enabling `skip_mount`, added kernel-owned advisory `flock` serialization plus conservative legacy-lock migration, and added transaction rollback/recovery with storage barriers for signals, process death, and sudden restart.
- Added safe custom-font deletion, duplicate-content name updates, shared apply/import/delete serialization, symlink checks, private-by-default persistent storage, and 24-hour cleanup leases for abandoned import stages.
- Added WebUI callback watchdogs with authoritative status recovery, manual refresh, initialization/layout gates, operation progress, safe deletion controls, and clearer multi-warning diagnostics.
- Added keyboard-accessible radio navigation, truthful mixed Latin/Persian previews, lazy font loading, import-preview race protection, WebView renderability gating, and consistent 80-byte normalized custom names.
- Added explicit requirements/support documentation, storage and recovery guidance, a tested-device matrix, contributor/issue/PR templates, and clarified manager update-network behavior.
- Documented why crDroid's RRO-based picker can restart SystemUI but cannot activate this module's boot-bound replacement font files.
- Added in-manager `updateJson`, packaged project/license notices, centralized archive naming from `module.prop`, exact development dependencies, action pinning, reproducibility checks, and a least-privilege tag-gated draft-to-publish workflow.
- Expanded regressions for false-positive ROM layouts, live/stale locks, state-write rollback, staging cleanup, deletion, and release/update metadata.

This remains a prerelease until update-from-rc4, bundled/custom switching, System Default, removal, and reboot behavior receive a clean real-device smoke test.

## 0.1.0-rc4

- Fixed rc3 installation failures caused by treating optional persistent custom-preview restoration as a fatal installer prerequisite.
- Made a missing custom-font registry a clean no-op that does not create or lock external persistent storage.
- Made stale locks, unsafe roots, malformed metadata, unreadable entries, and preview copy failures recoverable with installer-visible diagnostics.
- Preserved unusable custom data in place and added a private `quarantine/skipped-custom-data.log` diagnostic instead of deleting user files.
- Retained the rc2 explicit-shell/`0644` extraction fix and explicit final runtime script permissions.
- Added installer regressions for absent, valid, corrupt, stale/locked, and unsafe persistent custom-font states.

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
