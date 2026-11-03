#!/bin/bash
# Build distribution artifacts without an Apple Developer account.
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_WORK="$PACKAGE_ROOT/.build/package"
PACKAGE_OUTPUT="$PACKAGE_ROOT/dist"
PACKAGE_TARGET="all"
PACKAGE_VERSION=""
PACKAGE_BUILD_NUMBER=""
PACKAGE_SKIP_BUILD=0
PACKAGE_TARGET_SET=0
PACKAGE_STAGE=""

usage() {
    cat <<'USAGE'
Usage: bash Scripts/package.sh [all|dmg|ipa] [options]

  all                 Build a universal macOS DMG and unsigned device IPA (default).
  dmg                 Build the DMG only; the app is ad-hoc signed, not notarized.
  ipa                 Build an unsigned arm64 iPhone/iPad IPA, ready for re-signing.
  --version X.Y.Z     Override the app marketing version for this build.
  --build-number N   Override CFBundleVersion with a positive integer.
  --output-dir PATH  Artifact directory (default: <project>/dist).
  --skip-build       Repackage the last build under .build/package.
  -h, --help         Show this help.

Requires macOS and Xcode 26+ with the matching device SDKs.
DMG packaging also requires Python 3.10+; set PYTHON_BIN to choose an interpreter.
USAGE
}

fail() { printf '[Lexisle] %s\n' "$*" >&2; exit 1; }
need_value() { [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a value."; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        all|dmg|ipa)
            [[ "$PACKAGE_TARGET_SET" -eq 0 ]] || fail "Specify only one package target."
            PACKAGE_TARGET="$1"; PACKAGE_TARGET_SET=1; shift ;;
        --version) need_value "$@"; PACKAGE_VERSION="$2"; shift 2 ;;
        --build-number) need_value "$@"; PACKAGE_BUILD_NUMBER="$2"; shift 2 ;;
        --output-dir) need_value "$@"; PACKAGE_OUTPUT="$2"; shift 2 ;;
        --skip-build) PACKAGE_SKIP_BUILD=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; fail "Unknown argument: $1" ;;
    esac
done

[[ -z "$PACKAGE_VERSION" || "$PACKAGE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must be X.Y.Z (without a v prefix)."
[[ -z "$PACKAGE_BUILD_NUMBER" || "$PACKAGE_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail "Build number must be a positive integer."
[[ "$(uname -s)" == "Darwin" ]] || fail "Run this script on macOS."

choose_python() {
    local candidate minimum=9
    [[ "$PACKAGE_TARGET" == "ipa" ]] || minimum=10
    if [[ -n "${PYTHON_BIN:-}" ]]; then
        "$PYTHON_BIN" -c "import sys; sys.exit(sys.version_info < (3, $minimum))" || fail "PYTHON_BIN requires Python 3.$minimum+."
        PACKAGE_PYTHON="$PYTHON_BIN"
        return
    fi
    for candidate in python3.14 python3.13 python3.12 python3.11 python3.10 python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "import sys; sys.exit(sys.version_info < (3, $minimum))"; then
            PACKAGE_PYTHON="$(command -v "$candidate")"
            return
        fi
    done
    fail "Install Python 3.$minimum+ or set PYTHON_BIN."
}
choose_python

PACKAGE_OUTPUT="$("$PACKAGE_PYTHON" -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$PACKAGE_OUTPUT")"
PACKAGE_APP_NAME="$(sed -n 's/^APP_ENGLISH_NAME[[:space:]]*=[[:space:]]*//p' "$PACKAGE_ROOT/Config/Brand.xcconfig")"
PACKAGE_DISPLAY_NAME="$(sed -n 's/^APP_DISPLAY_NAME[[:space:]]*=[[:space:]]*//p' "$PACKAGE_ROOT/Config/Brand.xcconfig")"
[[ "$PACKAGE_APP_NAME" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || fail "Invalid APP_ENGLISH_NAME in Config/Brand.xcconfig."
[[ -n "$PACKAGE_DISPLAY_NAME" ]] || fail "Missing APP_DISPLAY_NAME in Config/Brand.xcconfig."
PACKAGE_UTILS="$PACKAGE_ROOT/Scripts/packaging/artifact_utils.py"

for tool in xcodebuild xcrun hdiutil codesign ditto; do
    command -v "$tool" >/dev/null 2>&1 || fail "Missing required tool: $tool"
done
XCODE_MAJOR="$(xcodebuild -version | awk '/^Xcode / {split($2, version, "."); print version[1]}')"
[[ "$XCODE_MAJOR" =~ ^[0-9]+$ && "$XCODE_MAJOR" -ge 26 ]] || fail "Select Xcode 26+ using DEVELOPER_DIR or xcode-select."

mkdir -p "$PACKAGE_WORK/logs" "$PACKAGE_OUTPUT"
PACKAGE_STAGE="$(mktemp -d "$PACKAGE_WORK/stage.XXXXXX")"
cleanup() {
    local code=$?
    if [[ -n "$PACKAGE_STAGE" && -d "$PACKAGE_STAGE" ]]; then
        rm -rf -- "$PACKAGE_STAGE"
    fi
    if [[ "$code" -ne 0 ]]; then printf '[Lexisle] Packaging failed. Build logs: %s/logs\n' "$PACKAGE_WORK" >&2; fi
}
trap cleanup EXIT

BUILD_ARGUMENTS=(
    -project "$PACKAGE_ROOT/WordAtlas.xcodeproj"
    -configuration Release
    ONLY_ACTIVE_ARCH=NO
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY=
    DEVELOPMENT_TEAM=
    ENABLE_DEBUG_DYLIB=NO
    WORD_ATLAS_CLOUD_ENABLED=NO
)
[[ -z "$PACKAGE_VERSION" ]] || BUILD_ARGUMENTS+=("MARKETING_VERSION=$PACKAGE_VERSION")
[[ -z "$PACKAGE_BUILD_NUMBER" ]] || BUILD_ARGUMENTS+=("CURRENT_PROJECT_VERSION=$PACKAGE_BUILD_NUMBER")

if [[ "$PACKAGE_SKIP_BUILD" -eq 0 ]]; then
    "$PACKAGE_PYTHON" "$PACKAGE_ROOT/Scripts/generate_project.py"
fi

build_with_log() {
    local log="$1"
    shift
    if ! "$@" > "$log" 2>&1; then
        tail -n 80 "$log" >&2
        fail "xcodebuild failed. Full log: $log"
    fi
}

check_metadata() {
    local app="$1" platform="$2" version number
    version="$("$PACKAGE_PYTHON" "$PACKAGE_UTILS" metadata "$app" --platform "$platform" --field CFBundleShortVersionString)"
    number="$("$PACKAGE_PYTHON" "$PACKAGE_UTILS" metadata "$app" --platform "$platform" --field CFBundleVersion)"
    [[ -z "$PACKAGE_VERSION" || "$version" == "$PACKAGE_VERSION" ]] || fail "Cached app version differs from --version; rebuild it."
    [[ -z "$PACKAGE_BUILD_NUMBER" || "$number" == "$PACKAGE_BUILD_NUMBER" ]] || fail "Cached app build differs from --build-number; rebuild it."
    printf '%s\n' "$version"
}

package_dmg() {
    local app="$PACKAGE_WORK/macos/$PACKAGE_APP_NAME.app"
    local derived="$PACKAGE_WORK/macos/DerivedData"
    local venv="$PACKAGE_WORK/dmg-venv"
    local version filename
    if [[ "$PACKAGE_SKIP_BUILD" -eq 0 ]]; then
        printf '[Lexisle] Building universal macOS Release…\n'
        build_with_log "$PACKAGE_WORK/logs/macos-build.log" xcodebuild "${BUILD_ARGUMENTS[@]}" \
            -scheme WordAtlas-macOS -destination 'generic/platform=macOS' -sdk macosx \
            -derivedDataPath "$derived" 'ARCHS=arm64 x86_64' build
        mkdir -p "$PACKAGE_WORK/macos"
        rm -rf -- "$app"
        /usr/bin/ditto "$derived/Build/Products/Release/$PACKAGE_APP_NAME.app" "$app"
        /usr/bin/codesign --force --sign - --timestamp=none --entitlements "$PACKAGE_ROOT/Config/macOS.entitlements" "$app"
    fi
    [[ -d "$app" ]] || fail "No cached Mac app. Run the script without --skip-build."
    version="$(check_metadata "$app" macos)"
    "$PACKAGE_PYTHON" "$PACKAGE_UTILS" verify-app "$app" --platform macos

    if [[ ! -x "$venv/bin/python" ]]; then "$PACKAGE_PYTHON" -m venv "$venv"; fi
    if ! "$venv/bin/python" -c 'from importlib.metadata import version; assert version("dmgbuild")=="1.6.7" and version("ds-store")=="1.3.3" and version("mac-alias")=="2.2.3"' >/dev/null 2>&1; then
        "$venv/bin/python" -m pip --disable-pip-version-check install -r "$PACKAGE_ROOT/Scripts/packaging/dmg-requirements.txt" \
            > "$PACKAGE_WORK/logs/dmg-dependencies.log" 2>&1 || {
                tail -n 40 "$PACKAGE_WORK/logs/dmg-dependencies.log" >&2; fail "Could not install DMG packaging tools."
            }
    fi

    mkdir -p "$PACKAGE_WORK/tools" "$PACKAGE_WORK/artwork"
    printf '[Lexisle] Rendering installer artwork…\n'
    xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$PACKAGE_WORK/ModuleCache" \
        "$PACKAGE_ROOT/Scripts/packaging/GenerateDMGArtwork.swift" -o "$PACKAGE_WORK/tools/GenerateDMGArtwork"
    "$PACKAGE_WORK/tools/GenerateDMGArtwork" "$PACKAGE_WORK/artwork" "$PACKAGE_APP_NAME" "$PACKAGE_DISPLAY_NAME" "$version" \
        "$PACKAGE_ROOT/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Default.png"

    filename="$PACKAGE_APP_NAME-$version-macOS-universal.dmg"
    printf '[Lexisle] Creating %s…\n' "$filename"
    "$venv/bin/dmgbuild" -s "$PACKAGE_ROOT/Scripts/packaging/dmg-settings.py" \
        -D "app=$app" -D "name=$PACKAGE_APP_NAME" \
        -D "icon=$app/Contents/Resources/AppIcon.icns" -D "background=$PACKAGE_WORK/artwork/background.tiff" \
        "$PACKAGE_APP_NAME" "$PACKAGE_STAGE/$filename" > "$PACKAGE_WORK/logs/dmg-build.log" 2>&1 || {
            tail -n 60 "$PACKAGE_WORK/logs/dmg-build.log" >&2; fail "DMG creation failed."
        }
    "$PACKAGE_PYTHON" "$PACKAGE_UTILS" verify-dmg "$PACKAGE_STAGE/$filename" --app-name "$PACKAGE_APP_NAME"
    mv -f -- "$PACKAGE_STAGE/$filename" "$PACKAGE_OUTPUT/$filename"
    "$PACKAGE_PYTHON" "$PACKAGE_UTILS" checksum "$PACKAGE_OUTPUT/$filename"
    printf '[Lexisle] Ready: %s\n' "$PACKAGE_OUTPUT/$filename"
}

package_ipa() {
    local archive="$PACKAGE_WORK/ios/$PACKAGE_APP_NAME.xcarchive"
    local app="$PACKAGE_STAGE/Payload/$PACKAGE_APP_NAME.app"
    local version filename
    if [[ "$PACKAGE_SKIP_BUILD" -eq 0 ]]; then
        printf '[Lexisle] Archiving unsigned iPhone/iPad Release…\n'
        mkdir -p "$PACKAGE_WORK/ios"
        build_with_log "$PACKAGE_WORK/logs/ios-archive.log" xcodebuild "${BUILD_ARGUMENTS[@]}" \
            -scheme WordAtlas-iOS -destination 'generic/platform=iOS' -sdk iphoneos \
            -derivedDataPath "$PACKAGE_WORK/ios/DerivedData" -archivePath "$archive" \
            ARCHS=arm64 CODE_SIGN_ENTITLEMENTS= archive
    fi
    [[ -d "$archive/Products/Applications/$PACKAGE_APP_NAME.app" ]] || fail "No cached iOS archive. Run without --skip-build."
    mkdir -p "$PACKAGE_STAGE/Payload"
    /usr/bin/ditto "$archive/Products/Applications/$PACKAGE_APP_NAME.app" "$app"
    version="$(check_metadata "$app" ios)"
    "$PACKAGE_PYTHON" "$PACKAGE_UTILS" strip-ios-signatures "$app"
    filename="$PACKAGE_APP_NAME-$version-iOS-unsigned.ipa"
    /usr/bin/ditto -c -k --norsrc --noextattr --noqtn --keepParent "$PACKAGE_STAGE/Payload" "$PACKAGE_STAGE/$filename"
    "$PACKAGE_PYTHON" "$PACKAGE_UTILS" verify-ipa "$PACKAGE_STAGE/$filename" --app-name "$PACKAGE_APP_NAME"
    mv -f -- "$PACKAGE_STAGE/$filename" "$PACKAGE_OUTPUT/$filename"
    "$PACKAGE_PYTHON" "$PACKAGE_UTILS" checksum "$PACKAGE_OUTPUT/$filename"
    printf '[Lexisle] Ready: %s\n' "$PACKAGE_OUTPUT/$filename"
}

# Repackaging must not silently combine two unrelated cached builds.
if [[ "$PACKAGE_TARGET" == "all" && "$PACKAGE_SKIP_BUILD" -eq 1 ]]; then
    cached_mac="$PACKAGE_WORK/macos/$PACKAGE_APP_NAME.app"
    cached_ios="$PACKAGE_WORK/ios/$PACKAGE_APP_NAME.xcarchive/Products/Applications/$PACKAGE_APP_NAME.app"
    cached_mac_version="$(check_metadata "$cached_mac" macos)"
    cached_ios_version="$(check_metadata "$cached_ios" ios)"
    [[ "$cached_mac_version" == "$cached_ios_version" ]] || fail "Cached macOS and iOS versions differ; rebuild both platforms."
    mac_build="$("$PACKAGE_PYTHON" "$PACKAGE_UTILS" metadata "$cached_mac" --platform macos --field CFBundleVersion)"
    ios_build="$("$PACKAGE_PYTHON" "$PACKAGE_UTILS" metadata "$cached_ios" --platform ios --field CFBundleVersion)"
    [[ "$mac_build" == "$ios_build" ]] || fail "Cached macOS and iOS build numbers differ; rebuild both platforms."
fi

case "$PACKAGE_TARGET" in
    all) package_dmg; package_ipa ;;
    dmg) package_dmg ;;
    ipa) package_ipa ;;
esac
printf '[Lexisle] SHA-256 checksums are next to the packages.\n'
