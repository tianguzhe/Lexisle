#!/usr/bin/env python3
"""Validate the actual distribution bundles, rather than trusting a build's exit status."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile

MACHO_MAGICS = {bytes.fromhex(value) for value in (
    "feedface", "feedfacf", "cefaedfe", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"
)}


def run(*arguments):
    return subprocess.check_output(arguments, text=True, stderr=subprocess.STDOUT).strip()


def validate_info(info, label):
    if info.get("CFBundlePackageType") != "APPL":
        raise ValueError(f"Not an application bundle: {label}")
    executable = info.get("CFBundleExecutable", "")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", executable):
        raise ValueError(f"Invalid executable name in {label}")
    for key, pattern in [("CFBundleShortVersionString", r"\d+\.\d+\.\d+"), ("CFBundleVersion", r"[1-9]\d*")]:
        if not re.fullmatch(pattern, str(info.get(key, ""))):
            raise ValueError(f"Invalid {key} in {label}: {info.get(key)!r}")
    if str(info.get("WordAtlasCloudEnabled", "")).lower() not in {"no", "false", "0"}:
        raise ValueError("Distribution packages must use local Release configuration with CloudKit disabled")
    return executable


def metadata(app, platform):
    plist = app / ("Contents/Info.plist" if platform == "macos" else "Info.plist")
    with plist.open("rb") as source:
        info = plistlib.load(source)
    executable = validate_info(info, plist)
    binary = app / ("Contents/MacOS" if platform == "macos" else "") / executable
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise ValueError(f"Missing executable: {binary}")
    return info, binary


def has_signature(path):
    result = subprocess.run(["/usr/bin/codesign", "--display", str(path)], capture_output=True, text=True)
    if result.returncode == 0:
        return True
    if "not signed at all" in result.stderr:
        return False
    raise ValueError(f"Could not inspect code signature for {path}: {result.stderr.strip()}")


def macho_files(app):
    for path in app.rglob("*"):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as source:
                if source.read(4) in MACHO_MAGICS:
                    yield path


def verify_platform(binary, platform):
    expected_architectures = {"arm64", "x86_64"} if platform == "macos" else {"arm64"}
    architectures = set(run("/usr/bin/lipo", "-archs", str(binary)).split())
    if architectures != expected_architectures:
        raise ValueError(f"Expected {expected_architectures}, got {architectures}: {binary}")
    build = run("/usr/bin/xcrun", "vtool", "-show-build", str(binary))
    platforms = set(re.findall(r"^\s*platform\s+(\S+)\s*$", build, re.MULTILINE))
    expected_platform = "MACOS" if platform == "macos" else "IOS"
    if platforms != {expected_platform}:
        raise ValueError(f"Expected {expected_platform} device binary, got {platforms}")


def strip_ios(app):
    _, binary = metadata(app, "ios")
    verify_platform(binary, "ios")
    if has_signature(app):
        subprocess.check_call(["/usr/bin/codesign", "--remove-signature", str(app)])
    # arm64 linkers can add ad-hoc Mach-O signatures even with CODE_SIGNING_ALLOWED=NO.
    for path in macho_files(app):
        if has_signature(path):
            subprocess.check_call(["/usr/bin/codesign", "--remove-signature", str(path)])
    for path in sorted(app.rglob("*"), key=lambda value: len(value.parts), reverse=True):
        if path.name == "_CodeSignature" and path.is_dir():
            shutil.rmtree(path)
        elif path.name in {"embedded.mobileprovision", "embedded.provisionprofile"}:
            path.unlink()
    verify_app(app, "ios")


def verify_app(app, platform):
    info, binary = metadata(app, platform)
    verify_platform(binary, platform)
    if platform == "macos":
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
        signature = run("/usr/bin/codesign", "--display", "--verbose=2", str(app))
        if "Signature=adhoc" not in signature:
            raise ValueError("Expected an ad-hoc signed Mac application")
    else:
        if has_signature(app):
            raise ValueError("IPA application still has a code signature")
        for path in macho_files(app):
            if has_signature(path):
                raise ValueError(f"IPA still contains signed Mach-O code: {path}")
        for path in app.rglob("*"):
            if path.name in {"_CodeSignature", "embedded.mobileprovision", "embedded.provisionprofile"}:
                raise ValueError(f"IPA contains signing material: {path}")
    print(f"Verified {platform}: {info['CFBundleName']} {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")


def verify_ipa(path, app_name):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        expected = f"Payload/{app_name}.app/"
        if not names or any(name != "Payload/" and not name.startswith(expected) for name in names):
            raise ValueError("IPA must contain only Payload/<app>.app")
        if any(".." in Path(name).parts or name.startswith("/") for name in names):
            raise ValueError("Invalid archive entry")
        if len(set(names)) != len(names):
            raise ValueError("IPA contains duplicate ZIP entries")
        if any(part in {"_CodeSignature", "embedded.mobileprovision", "embedded.provisionprofile"}
               for name in names for part in Path(name).parts):
            raise ValueError("IPA contains signing material")
        with archive.open(expected + "Info.plist") as source:
            info = plistlib.load(source)
        executable_name = validate_info(info, path)
        executable = archive.getinfo(expected + executable_name)
        if not (executable.external_attr >> 16) & 0o111:
            raise ValueError("IPA executable permissions were lost")
        # Inspect archive bytes themselves. Flat temporary filenames avoid following ZIP symlinks.
        with tempfile.TemporaryDirectory(prefix="lexisle-ipa-verify-") as temporary:
            found_main = False
            for index, entry in enumerate(archive.infolist()):
                if entry.is_dir():
                    continue
                with archive.open(entry) as source:
                    magic = source.read(4)
                    if magic not in MACHO_MAGICS:
                        continue
                    binary = Path(temporary) / f"image-{index}"
                    with binary.open("wb") as output:
                        output.write(magic)
                        shutil.copyfileobj(source, output)
                if has_signature(binary):
                    raise ValueError(f"IPA still contains a Mach-O code signature: {entry.filename}")
                if entry.filename == executable.filename:
                    verify_platform(binary, "ios")
                    found_main = True
            if not found_main:
                raise ValueError("IPA main executable is not a Mach-O binary")
        invalid = archive.testzip()
        if invalid:
            raise ValueError(f"Corrupt ZIP entry: {invalid}")
    print(f"Verified unsigned IPA payload and device code: {path.name}")


def verify_dmg(path, app_name):
    run("/usr/bin/hdiutil", "verify", str(path))
    with tempfile.TemporaryDirectory(prefix="lexisle-dmg-verify-") as temporary:
        mount = Path(temporary) / "mount"
        mount.mkdir()
        attached = False
        try:
            subprocess.check_call([
                "/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(path)
            ], stdout=subprocess.DEVNULL)
            attached = True
            verify_app(mount / f"{app_name}.app", "macos")
            if not (mount / "Applications").is_symlink() or os.readlink(mount / "Applications") != "/Applications":
                raise ValueError("DMG is missing its Applications installation link")
            if not (mount / ".DS_Store").is_file():
                raise ValueError("DMG is missing its Finder layout")
        finally:
            # Use our mount path directly: macOS may report /private/var for a requested /var path.
            if attached or os.path.ismount(mount):
                detached = subprocess.run(["/usr/bin/hdiutil", "detach", "-quiet", str(mount)], capture_output=True)
                if detached.returncode:
                    subprocess.check_call(["/usr/bin/hdiutil", "detach", "-force", "-quiet", str(mount)])
    print(f"Verified DMG contents: {path.name}")


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    path.with_suffix(path.suffix + ".sha256").write_text(f"{digest.hexdigest()}  {path.name}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ["verify-app", "metadata", "strip-ios-signatures"]:
        command = commands.add_parser(name)
        command.add_argument("app", type=Path)
        if name != "strip-ios-signatures":
            command.add_argument("--platform", required=True, choices=["macos", "ios"])
        if name == "metadata":
            command.add_argument("--field", required=True)
    for name in ["verify-dmg", "verify-ipa"]:
        command = commands.add_parser(name)
        command.add_argument("path", type=Path)
        command.add_argument("--app-name", required=True)
    commands.add_parser("checksum").add_argument("path", type=Path)
    args = parser.parse_args()
    if args.command == "metadata":
        print(metadata(args.app, args.platform)[0][args.field])
    elif args.command == "verify-app":
        verify_app(args.app, args.platform)
    elif args.command == "strip-ios-signatures":
        strip_ios(args.app)
    elif args.command == "verify-dmg":
        verify_dmg(args.path, args.app_name)
    elif args.command == "verify-ipa":
        verify_ipa(args.path, args.app_name)
    elif args.command == "checksum":
        checksum(args.path)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        raise SystemExit(f"Artifact validation failed: {error}") from error
