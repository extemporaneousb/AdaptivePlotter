#!/bin/sh
set -eu

bundle=${1:?"usage: validate_local_app_bundle.sh PATH_TO_APP"}
plist="$bundle/Contents/Info.plist"
executable="$bundle/Contents/MacOS/AdaptivePlotter"

if [ ! -d "$bundle" ] || [ ! -f "$plist" ] || [ ! -x "$executable" ]; then
    echo "invalid AdaptivePlotter app-bundle structure: $bundle" >&2
    exit 1
fi

plutil -lint "$plist" >/dev/null

expect_plist_value() {
    key=$1
    expected=$2
    actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")
    if [ "$actual" != "$expected" ]; then
        echo "unexpected $key in $plist: '$actual' (expected '$expected')" >&2
        exit 1
    fi
}

expect_plist_value CFBundleExecutable AdaptivePlotter
expect_plist_value CFBundleIdentifier com.bullard.AdaptivePlotter
expect_plist_value CFBundlePackageType APPL
expect_plist_value CFBundleVersion 1
expect_plist_value CFBundleShortVersionString 0.1.0
expect_plist_value LSMinimumSystemVersion 14.0
expect_plist_value LSBackgroundOnly false
expect_plist_value LSUIElement false
expect_plist_value NSHighResolutionCapable true
expect_plist_value NSCameraUsageDescription \
    "AdaptivePlotter uses the selected local camera to display the plotter workspace and capture frames for visual measurements."

if ! verification=$(
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$bundle" 2>&1
); then
    printf '%s\n' "$verification" >&2
    echo "AdaptivePlotter app bundle has no valid strict code signature" >&2
    exit 1
fi

if ! /usr/bin/codesign \
    --verify \
    --deep \
    --strict \
    -R='identifier "com.bullard.AdaptivePlotter"' \
    "$bundle" >/dev/null 2>&1
then
    echo "AdaptivePlotter code signature does not carry the stable identifier" >&2
    exit 1
fi

signature_details=$(/usr/bin/codesign --display --verbose=4 "$bundle" 2>&1)
if ! printf '%s\n' "$signature_details" \
    | grep -Fqx 'Identifier=com.bullard.AdaptivePlotter'
then
    printf '%s\n' "$signature_details" >&2
    echo "AdaptivePlotter signature reports an unexpected identifier" >&2
    exit 1
fi
if printf '%s\n' "$signature_details" | grep -Fq 'Info.plist=not bound'; then
    printf '%s\n' "$signature_details" >&2
    echo "AdaptivePlotter signature is not bound to Contents/Info.plist" >&2
    exit 1
fi
if ! printf '%s\n' "$signature_details" \
    | grep -Eq '^Info\.plist entries=[1-9][0-9]*$'
then
    printf '%s\n' "$signature_details" >&2
    echo "AdaptivePlotter signature does not report a bound Info.plist" >&2
    exit 1
fi
