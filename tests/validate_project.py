#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = ROOT / "webroot/font-manifest.json"
PAYLOAD_LIST = ROOT / "scripts/payload-files.txt"
FONT_IDS = (
    "vazirmatn",
    "estedad",
    "sahel",
    "shabnam",
    "samim",
    "tanha",
    "gandom",
    "parastoo",
    "mikhak",
    "cairo",
    "noto-sans-arabic",
    "noto-kufi-arabic",
    "ibm-plex-sans-arabic",
)
TARGETS = {
    "NotoNaskhArabicUI-Regular.ttf": ("vazirmatn", "regular"),
    "NotoNaskhArabicUI-Bold.ttf": ("vazirmatn", "bold"),
    "NotoNaskhArabic-Regular.ttf": ("vazirmatn", "regular"),
    "NotoNaskhArabic-Bold.ttf": ("vazirmatn", "bold"),
}
REQUIRED_CODEPOINTS = {
    0x0621,
    0x0622,
    0x0624,
    0x0626,
    0x0627,
    0x0628,
    0x067E,
    0x062A,
    0x062B,
    0x062C,
    0x0686,
    0x062D,
    0x062E,
    0x062F,
    0x0630,
    0x0631,
    0x0632,
    0x0698,
    0x0633,
    0x0634,
    0x0635,
    0x0636,
    0x0637,
    0x0638,
    0x0639,
    0x063A,
    0x0641,
    0x0642,
    0x06A9,
    0x06AF,
    0x0644,
    0x0645,
    0x0646,
    0x0648,
    0x0647,
    0x06CC,
    *range(0x06F0, 0x06FA),
}


def fail(message: str) -> None:
    raise AssertionError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def payload_files() -> list[str]:
    paths = [
        line.strip()
        for line in PAYLOAD_LIST.read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if paths != sorted(paths):
        fail("Payload list must be bytewise sorted")
    if len(paths) != len(set(paths)):
        fail("Payload list contains duplicates")
    for relative in paths:
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            fail(f"Unsafe payload path: {relative}")
        if not (ROOT / path).is_file():
            fail(f"Missing payload file: {relative}")
        if "iransans" in relative.lower():
            fail("Unlicensed IRANSans file appears in the release payload")
    return paths


def module_properties() -> None:
    values: dict[str, str] = {}
    for line in (ROOT / "module.prop").read_text().splitlines():
        if not line or "=" not in line:
            fail("Malformed module.prop line")
        key, value = line.split("=", 1)
        if key in values or not value:
            fail(f"Invalid module.prop field: {key}")
        values[key] = value
    expected = {
        "id": "persian_font_switcher",
        "name": "Persian Font Switcher",
        "version": "0.1.0-rc4",
        "versionCode": "103",
        "author": "Yasin Fadaee",
    }
    for key, value in expected.items():
        if values.get(key) != value:
            fail(f"Unexpected module.prop {key}")


def validate_font(path: Path, expected_hash: str, expected_weight: int, non_latin: bool) -> None:
    if sha256(path) != expected_hash:
        fail(f"Checksum mismatch: {path.relative_to(ROOT)}")
    font = TTFont(path, lazy=True)
    try:
        for table in ("cmap", "GDEF", "GPOS", "GSUB", "OS/2", "name"):
            if table not in font:
                fail(f"Missing {table} table: {path.relative_to(ROOT)}")
        cmap = font.getBestCmap() or {}
        missing = REQUIRED_CODEPOINTS.difference(cmap)
        if missing:
            fail(f"Missing required glyphs in {path.relative_to(ROOT)}: {sorted(missing)}")
        if font["OS/2"].usWeightClass != expected_weight:
            fail(f"Unexpected weight class: {path.relative_to(ROOT)}")
        has_latin = 0x0041 in cmap or 0x0061 in cmap
        if non_latin and has_latin:
            fail(f"Non-Latin build contains Latin A/a: {path.relative_to(ROOT)}")
        names = font["name"].names
        for name_id, label in ((1, "family"), (2, "subfamily"), (5, "version")):
            values = [record.toUnicode().strip() for record in names if record.nameID == name_id]
            if not any(values):
                fail(f"Missing nonempty {label} name metadata: {path.relative_to(ROOT)}")
    finally:
        font.close()


def manifest_and_fonts() -> dict:
    manifest = json.loads(MANIFEST_PATH.read_text())
    if manifest.get("schema") != 2 or manifest.get("projectVersion") != "0.1.0-rc4":
        fail("Unsupported manifest schema/version")
    if manifest.get("systemDefault", {}).get("id") != "system-default":
        fail("System Default manifest entry is missing")
    fonts = manifest.get("fonts")
    if not isinstance(fonts, list) or tuple(font["id"] for font in fonts) != FONT_IDS:
        fail("Unexpected initial font set/order")
    seen: set[str] = {"system-default"}
    for font in fonts:
        font_id = font["id"]
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,31}", font_id) or font_id in seen:
            fail(f"Unsafe or duplicate font ID: {font_id}")
        seen.add(font_id)
        if not font["license"] or not font["source"].startswith("https://github.com/"):
            fail(f"Invalid provenance: {font_id}")
        for weight, hash_key in (("regular", "sha256Regular"), ("bold", "sha256Bold")):
            expected_relative = f"assets/fonts/{font_id}/{weight}.ttf"
            if font[weight] != expected_relative:
                fail(f"Unsafe manifest path: {font_id}/{weight}")
            source = ROOT / expected_relative
            expected_weight = 400 if weight == "regular" or font.get("boldStrategy") == "duplicate-regular" else 700
            validate_font(source, font[hash_key], expected_weight, bool(font["nonLatin"]))
            preview = ROOT / "webroot" / font[f"preview{weight.title()}"]
            expected_preview = ROOT / f"webroot/fonts/{font_id}/{weight}.ttf"
            if preview.resolve() != expected_preview.resolve():
                fail(f"Unexpected preview path: {font_id}/{weight}")
            if source.read_bytes() != preview.read_bytes():
                fail(f"Preview differs from source: {font_id}/{weight}")
        license_path = ROOT / font["licensePath"]
        license_text = license_path.read_text(errors="replace")
        if font_id == "tanha":
            if "Bitstream Vera" not in license_text or "Apache" not in license_text:
                fail("Tanha combined redistribution notices are incomplete")
        elif "SIL OPEN FONT LICENSE" not in license_text:
            fail(f"Missing OFL text: {font_id}")
        extra_license = font.get("additionalLicensePath")
        if extra_license and "Apache License" not in (ROOT / extra_license).read_text(errors="replace"):
            fail(f"Missing additional license: {font_id}")
        if font.get("boldStrategy") == "duplicate-regular" and source.read_bytes() != (ROOT / font["regular"]).read_bytes():
            fail(f"Declared duplicate Regular/Bold files differ: {font_id}")
        archive_hash = font.get("archiveSha256")
        if archive_hash and not re.fullmatch(r"[0-9a-f]{64}", archive_hash):
            fail(f"Invalid upstream archive hash: {font_id}")
        if not archive_hash and not re.fullmatch(r"[0-9a-f]{40}", font.get("sourceCommit", "")):
            fail(f"Missing pinned upstream archive/commit: {font_id}")
    if any("iransans" in font["id"].lower() for font in fonts):
        fail("Unlicensed IRANSans must not be redistributed")
    return manifest


def initial_overlay() -> None:
    for target, (font_id, weight) in TARGETS.items():
        source = ROOT / f"assets/fonts/{font_id}/{weight}.ttf"
        destination = ROOT / "system/fonts" / target
        if source.read_bytes() != destination.read_bytes():
            fail(f"Initial overlay mapping mismatch: {target}")


def static_webui() -> None:
    html = (ROOT / "webroot/index.html").read_text()
    js = (ROOT / "webroot/app.js").read_text()
    css = (ROOT / "webroot/style.css").read_text()
    for marker in ("font-list", "active-font", "selected-font", "font-search", "custom-regular", "custom-bold", "apply-button", "fontloader-status", "Content-Security-Policy"):
        if marker not in html:
            fail(f"Missing WebUI marker: {marker}")
    if re.search(r"https?://|(?:^|[\"'])//", html + js + css, re.MULTILINE):
        fail("WebUI code contains an external URL or protocol-relative dependency")
    for forbidden in ("eval(", "new function", "xmlhttprequest", "websocket", "ksu.spawn", "killall", "ctl.restart", "mount --bind"):
        if forbidden in js.lower():
            fail(f"Forbidden WebUI behavior: {forbidden}")
    for marker in ("new FontFace", "fileOutputStream", "validateFontFile", "PfsFontValidator", "restart_required"):
        if marker not in js:
            fail(f"Missing WebUI feature: {marker}")
    if "SAFE_ID" not in js or "optionFor(args[0])" not in js:
        fail("WebUI selection lacks syntax and manifest allowlists")


def syntax_and_modes() -> None:
    shell_files = [ROOT / "customize.sh", *sorted((ROOT / "scripts").glob("*.sh")), *sorted((ROOT / "tests").glob("*.sh"))]
    for script in shell_files:
        subprocess.run(["sh", "-n", str(script)], check=True)
        if script.parent.name == "scripts" and script.name not in {"build.sh", "validate.sh"} and not os.access(script, os.X_OK):
            fail(f"Runtime script is not executable: {script.relative_to(ROOT)}")
    node = shutil.which("node")
    if node:
        subprocess.run([node, "--check", str(ROOT / "webroot/app.js")], check=True)
        subprocess.run([node, "--check", str(ROOT / "webroot/font-validator.js")], check=True)
        subprocess.run([node, str(ROOT / "tests/test_font_validator.js")], check=True)
    reboot_script = (ROOT / "scripts/reboot-device.sh").read_text()
    if "if /system/bin/svc power reboot; then" not in reboot_script or reboot_script.index("svc power reboot") > reboot_script.index("/system/bin/reboot"):
        fail("Reboot action does not retain the svc-to-reboot fallback order")


def archive_validation(archive_path: Path, expected: list[str]) -> None:
    if not archive_path.is_file():
        fail(f"Archive does not exist: {archive_path}")
    with zipfile.ZipFile(archive_path) as archive:
        names = [info.filename for info in archive.infolist() if not info.is_dir()]
        if names != expected:
            fail("ZIP file list/order does not match the declared payload")
        for info in archive.infolist():
            name = info.filename
            if name.startswith("/") or ".." in Path(name).parts or re.search(
                r"(^|/)(\.git|__MACOSX)(/|$)|(^|/)\.DS_Store$|(~|\.swp|\.tmp)$", name
            ):
                fail(f"Unsafe or unrelated ZIP entry: {name}")
            mode = stat.S_IMODE(info.external_attr >> 16)
            expected_mode = (
                0o755
                if name == "customize.sh" or (name.startswith("scripts/") and name.endswith(".sh"))
                else 0o600
                if name.startswith("state/")
                else 0o644
            )
            if mode != expected_mode:
                fail(f"Unexpected ZIP mode {mode:o}: {name}")
        with tempfile.TemporaryDirectory() as temp:
            extracted = Path(temp)
            archive.extractall(extracted)
            actual = sorted(
                path.relative_to(extracted).as_posix()
                for path in extracted.rglob("*")
                if path.is_file()
            )
            if actual != expected:
                fail("Clean extraction layout differs from payload")
            for relative in expected:
                if (ROOT / relative).read_bytes() != (extracted / relative).read_bytes():
                    fail(f"Extracted file differs from source: {relative}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    if not args.source_only and args.archive is None:
        parser.error("use --source-only or --archive")

    expected = payload_files()
    module_properties()
    manifest_and_fonts()
    initial_overlay()
    static_webui()
    syntax_and_modes()
    if args.archive is not None:
        archive_validation(args.archive.resolve(), expected)
    print("Project validation passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, KeyError, ValueError, zipfile.BadZipFile) as error:
        print(f"Validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
