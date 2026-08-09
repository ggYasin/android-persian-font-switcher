# Contributing

Contributions are welcome when they preserve the module's narrow, fail-closed system boundary. Start with the [requirements](docs/REQUIREMENTS.md), [architecture](docs/ARCHITECTURE.md), and [security policy](SECURITY.md).

## Development setup

The supported validation host is Linux. Required tools are a POSIX shell, Python 3.10+, Node.js 20+, Info-ZIP `zip`, GNU `sha256sum`/`stat`, util-linux `flock`, and the exact FontTools version pinned in `requirements-dev.txt`.

```sh
python3 -m pip install -r requirements-dev.txt
./scripts/build.sh
./scripts/validate.sh
```

The validator checks font metadata/provenance, licenses, WebUI syntax and SFNT rejection, every bundled selection, active-versus-selected status, failure rollback, custom persistence/removal, installer behavior, payload permissions, archive contents, and deterministic output. Do not submit generated ZIP or checksum files; they are CI/release artifacts.

## Compatibility boundaries

- Runtime scripts must remain compatible with Android `/system/bin/sh` and KernelSU's BusyBox environment. Avoid Bash-only syntax and optional host-only utilities.
- Keep privileged WebUI calls limited to fixed module-local scripts with strict allowlisted arguments. Display names, picker paths, URIs, and manifest prose must never become shell input.
- Preserve the four-target transaction, `skip_mount` fail-safe, System Default behavior, and normal-reboot requirement unless a separately tested layout/provider design is proposed.
- Do not add live bind mounts, provider-owned path writes, automatic reboot, zygote/SystemUI kill shortcuts, telemetry, or network resources to the WebUI.
- New device/layout support requires real font-configuration evidence, capability checks, fixtures, application tests, and a documented device report. A marketing name or Android version is not sufficient.

## Fonts and licensing

Follow [Adding a font](docs/ADDING_FONTS.md). Only unchanged, pinned, redistributable upstream files are accepted. Do not open an issue or pull request containing commercial/proprietary fonts, APK-extracted assets, personal license files, or unclear mirrors.

## Pull requests

1. Keep changes focused and explain the user-visible behavior and failure model.
2. Add regression coverage for every changed privileged path or compatibility rule.
3. Run the complete build/validation commands above.
4. Update requirements, architecture, compatibility, security, and changelog text when their claims change.
5. Do not bump/release a version for documentation-only changes. Payload behavior changes require a new prerelease and monotonically increasing `versionCode`.

Bug and device reports should include device codename, exact ROM/API, KernelSU Next Manager, mount provider, FontLoader state, module version, install/update path, installer output, and WebUI Active/Selected/ROM layout status. Remove serials, tokens, private paths, and other secrets.
