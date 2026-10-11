#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
configuration=${1:-debug}
case "$configuration" in
    release|debug) ;;
    *) echo "unsupported app build configuration: $configuration" >&2; exit 1 ;;
esac
binary="$project_root/.build/$configuration/PortraitStudio"
output=${2:-"$project_root/.build/PortraitStudio.app"}
case "$output" in
    /*/PortraitStudio.app) ;;
    *) echo "output must be an absolute path ending in /PortraitStudio.app" >&2; exit 1 ;;
esac
if [ -L "$output" ]; then
    echo "refusing to replace a symbolic-link bundle: $output" >&2
    exit 1
fi
if [ -e "$output" ]; then
    sh "$project_root/Scripts/validate_portrait_studio_app_bundle.sh" "$output"
    if /usr/sbin/lsof -t "$output/Contents/MacOS/PortraitStudio" >/dev/null 2>&1; then
        echo "quit the existing PortraitStudio app before replacing its bundle" >&2
        exit 1
    fi
fi
template="$project_root/Resources/PortraitStudio-Info.plist"
requested_signing_identity=${PORTRAITSTUDIO_CODESIGN_IDENTITY:-"AdaptivePlotter Local Development"}
signing_keychain=${PORTRAITSTUDIO_CODESIGN_KEYCHAIN:-}

if [ ! -x "$binary" ]; then
    echo "PortraitStudio $configuration executable is missing; run 'make portrait-studio-app APP_CONFIGURATION=$configuration' first" >&2
    exit 1
fi
if [ ! -f "$template" ]; then
    echo "local app Info.plist template is missing: $template" >&2
    exit 1
fi

staging_root=$(mktemp -d "$project_root/.build/.PortraitStudio-app.XXXXXX")
staging_bundle="$staging_root/PortraitStudio.app"
trap 'rm -rf "$staging_root"' EXIT HUP INT TERM

mkdir -p "$staging_bundle/Contents/MacOS"
install -m 755 "$binary" "$staging_bundle/Contents/MacOS/PortraitStudio"
install -m 644 "$template" "$staging_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :PortraitStudioBuildConfiguration string $configuration" \
    "$staging_bundle/Contents/Info.plist"

signing_identity=-
signing_mode=ad-hoc
if [ "$requested_signing_identity" != "-" ]; then
    if [ -n "$signing_keychain" ]; then
        available_identities=$(
            /usr/bin/security find-identity -v -p codesigning "$signing_keychain" 2>/dev/null \
                || true
        )
    else
        available_identities=$(
            /usr/bin/security find-identity -v -p codesigning 2>/dev/null || true
        )
    fi
    if printf '%s\n' "$available_identities" \
        | grep -Fq "\"$requested_signing_identity\""
    then
        signing_identity=$requested_signing_identity
        signing_mode=stable-local
    fi
fi

if [ "$signing_mode" = stable-local ] && [ -n "$signing_keychain" ]; then
    /usr/bin/codesign \
        --force \
        --deep \
        --sign "$signing_identity" \
        --keychain "$signing_keychain" \
        --identifier com.bullard.PortraitStudio \
        --timestamp=none \
        "$staging_bundle"
else
    /usr/bin/codesign \
        --force \
        --deep \
        --sign "$signing_identity" \
        --identifier com.bullard.PortraitStudio \
        --timestamp=none \
        "$staging_bundle"
fi

sh "$project_root/Scripts/validate_portrait_studio_app_bundle.sh" "$staging_bundle"

mkdir -p "$(dirname "$output")"
rm -rf "$output"
mv "$staging_bundle" "$output"

sh "$project_root/Scripts/validate_portrait_studio_app_bundle.sh" "$output"
echo "PortraitStudio build: $configuration" >&2
echo "PortraitStudio signing: $signing_mode ($signing_identity)" >&2
echo "$output"
