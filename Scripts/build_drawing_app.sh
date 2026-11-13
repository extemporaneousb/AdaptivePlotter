#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
product=${1:?product required}
shift
case "$product" in
    AdaptivePlotter) validator=validate_local_app_bundle.sh ;;
    PortraitStudio) validator=validate_portrait_studio_app_bundle.sh ;;
    *) echo "unsupported product: $product" >&2; exit 1 ;;
esac
configuration=${1:-debug}
case "$configuration" in
    release|debug) ;;
    *) echo "unsupported app build configuration: $configuration" >&2; exit 1 ;;
esac
binary_directory=${APP_BINARY_DIRECTORY-"$project_root/.build/$configuration"}
case "$binary_directory" in
    /*) ;;
    *) echo "APP_BINARY_DIRECTORY must be an absolute SwiftPM binary directory" >&2; exit 1 ;;
esac
binary="$binary_directory/${product}"
output=${2:-"$project_root/.build/${product}.app"}
case "$output" in
    /*/${product}.app) ;;
    *) echo "output must be an absolute path ending in /${product}.app" >&2; exit 1 ;;
esac
if [ -L "$output" ]; then
    echo "refusing to replace a symbolic-link bundle: $output" >&2
    exit 1
fi
if [ -e "$output" ]; then
    existing_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$output/Contents/Info.plist")
    if [ "$existing_identifier" != "com.bullard.$product" ]; then
        echo "refusing unrelated existing bundle: $output" >&2; exit 1
    fi
    if /usr/sbin/lsof -t "$output/Contents/MacOS/${product}" >/dev/null 2>&1; then
        echo "quit the existing ${product} app before replacing its bundle" >&2
        exit 1
    fi
fi
template="$project_root/Resources/${product}-Info.plist"
if [ "$product" = AdaptivePlotter ]; then
    requested_signing_identity=${ADAPTIVEPLOTTER_CODESIGN_IDENTITY:-"AdaptivePlotter Local Development"}
    signing_keychain=${ADAPTIVEPLOTTER_CODESIGN_KEYCHAIN:-}
else
    requested_signing_identity=${PORTRAITSTUDIO_CODESIGN_IDENTITY:-"AdaptivePlotter Local Development"}
    signing_keychain=${PORTRAITSTUDIO_CODESIGN_KEYCHAIN:-}
fi

if [ ! -x "$binary" ]; then
    echo "${product} $configuration executable is missing; build the $product product with configuration $configuration first" >&2
    exit 1
fi
if [ ! -f "$template" ]; then
    echo "local app Info.plist template is missing: $template" >&2
    exit 1
fi

mkdir -p "$project_root/.build"
staging_root=$(mktemp -d "$project_root/.build/.${product}-app.XXXXXX")
staging_bundle="$staging_root/${product}.app"
trap 'rm -rf "$staging_root"' EXIT HUP INT TERM

mkdir -p "$staging_bundle/Contents/MacOS" "$staging_bundle/Contents/Resources"
install -m 644 "$project_root/Resources/$product.icns" "$staging_bundle/Contents/Resources/$product.icns"
install -m 755 "$binary" "$staging_bundle/Contents/MacOS/${product}"
install -m 644 "$template" "$staging_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :${product}BuildConfiguration string $configuration" \
    "$staging_bundle/Contents/Info.plist"
build_input_sha256=$(/usr/bin/shasum -a 256 "$binary" | /usr/bin/awk '{print $1}')
/usr/libexec/PlistBuddy -c "Add :${product}BuildInputSHA256 string $build_input_sha256" \
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
        --identifier com.bullard.${product} \
        --timestamp=none \
        "$staging_bundle"
else
    /usr/bin/codesign \
        --force \
        --deep \
        --sign "$signing_identity" \
        --identifier com.bullard.${product} \
        --timestamp=none \
        "$staging_bundle"
fi

sh "$project_root/Scripts/$validator" "$staging_bundle" "$binary" "$configuration"

mkdir -p "$(dirname "$output")"
rm -rf "$output"
mv "$staging_bundle" "$output"

sh "$project_root/Scripts/$validator" "$output" "$binary" "$configuration"
echo "${product} source executable: $binary ($build_input_sha256)" >&2
echo "${product} build: $configuration" >&2
echo "${product} signing: $signing_mode ($signing_identity)" >&2
echo "$output"
