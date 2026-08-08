# Adding a font

New font contributions must be small, UI-suitable, and legally redistributable.

1. Identify the official author/project repository and a pinned release or commit.
2. Read the font license. A public download is not a redistribution license.
3. Use official static Regular (weight 400) and Bold (weight 700) TTF/OTF files.
4. Prefer an official non-Latin or UI variant when one exists; do not strip glyphs solely for this project.
5. Copy unchanged files to `assets/fonts/<id>/regular.ttf` and `bold.ttf`.
6. Retain the upstream license in the same directory, including additional notices when required.
7. Add the font once to `webroot/font-manifest.json`, including version, variant, author, license, source release, archive hash, file hashes, and canonical paths.
8. Copy byte-identical preview files to `webroot/fonts/<id>/`.
9. Add the new payload paths to `scripts/payload-files.txt`.
10. Add WebUI preview `@font-face` rules and extend the validator's expected initial font set.
11. Run the complete build and validation suite.

Validation requires Arabic shaping tables, Regular/Bold weight metadata, Persian characters such as `پ چ ژ گ ی`, ZWNJ, Persian digits, source hashes, license text, and byte-identical previews.

Commercial fonts, IRANSans binaries, unlicensed mirrors, unclear freeware, repackaged APK assets, or fonts requiring an individual purchase/license are not accepted.
