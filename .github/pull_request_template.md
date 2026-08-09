## What changed

Describe the user-visible change and why it is needed.

## Compatibility and failure behavior

- [ ] The existing four-target overlay and reboot model remain intact, or the new model has device evidence and documentation.
- [ ] Privileged inputs remain fixed/allowlisted and no display name, URI, or arbitrary path reaches a shell command.
- [ ] Failure and interruption behavior favors a complete prior overlay or System Default, never a partial font family.

## Validation

- [ ] `./scripts/build.sh`
- [ ] `./scripts/validate.sh`
- [ ] Relevant device/ROM testing is described below.

Device, ROM/API, KernelSU Next, mount provider, FontLoader, and result:

## Licensing

- [ ] No proprietary font, secret, generated ZIP, or unrelated binary is included.
- [ ] New font files include pinned provenance, hashes, and redistribution licenses.
