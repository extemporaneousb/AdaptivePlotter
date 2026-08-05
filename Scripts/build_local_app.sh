#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
binary="$project_root/.build/debug/AdaptivePlotter"
output="$project_root/.build/AdaptivePlotter.app"
template="$project_root/Resources/AdaptivePlotter-Info.plist"
requested_signing_identity=${ADAPTIVEPLOTTER_CODESIGN_IDENTITY:-"AdaptivePlotter Local Development"}
signing_keychain=${ADAPTIVEPLOTTER_CODESIGN_KEYCHAIN:-}

if [ ! -x "$binary" ]; then
    echo "AdaptivePlotter executable is missing; run 'make build' first" >&2
    exit 1
fi
if [ ! -f "$template" ]; then
    echo "local app Info.plist template is missing: $template" >&2
    exit 1
fi

staging_root=$(mktemp -d "$project_root/.build/.AdaptivePlotter-app.XXXXXX")
staging_bundle="$staging_root/AdaptivePlotter.app"
trap 'rm -rf "$staging_root"' EXIT HUP INT TERM

mkdir -p "$staging_bundle/Contents/MacOS"
install -m 755 "$binary" "$staging_bundle/Contents/MacOS/AdaptivePlotter"
install -m 644 "$template" "$staging_bundle/Contents/Info.plist"

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
        --identifier com.bullard.AdaptivePlotter \
        --timestamp=none \
        "$staging_bundle"
else
    /usr/bin/codesign \
        --force \
        --deep \
        --sign "$signing_identity" \
        --identifier com.bullard.AdaptivePlotter \
        --timestamp=none \
        "$staging_bundle"
fi

sh "$project_root/Scripts/validate_local_app_bundle.sh" "$staging_bundle"

if [ "$output" != "$project_root/.build/AdaptivePlotter.app" ]; then
    echo "refusing unexpected app-bundle output path: $output" >&2
    exit 1
fi
rm -rf "$output"
mv "$staging_bundle" "$output"

sh "$project_root/Scripts/validate_local_app_bundle.sh" "$output"
echo "AdaptivePlotter signing: $signing_mode ($signing_identity)" >&2
echo "$output"
