#!/bin/sh
# Read-only checks of actual prepared bundles; never executes either app.
set -eu
project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
binary_directory=${1:?"usage: test_drawing_app_build_inputs.sh SWIFTPM_BINARY_DIRECTORY [debug|release]"}
configuration=${2:-debug}
case "$configuration" in
    debug) wrong_configuration=release ;;
    release) wrong_configuration=debug ;;
    *) echo "unsupported configuration: $configuration" >&2; exit 1 ;;
esac
for product in AdaptivePlotter PortraitStudio; do
    case "$product" in
        AdaptivePlotter) validator="$project_root/Scripts/validate_local_app_bundle.sh"; other=PortraitStudio ;;
        PortraitStudio) validator="$project_root/Scripts/validate_portrait_studio_app_bundle.sh"; other=AdaptivePlotter ;;
    esac
    bundle="$project_root/.build/$product.app"
    sh "$validator" "$bundle" "$binary_directory/$product" "$configuration"
    case "$product" in
        AdaptivePlotter) builder="$project_root/Scripts/build_local_app.sh" ;;
        PortraitStudio) builder="$project_root/Scripts/build_portrait_studio_app.sh" ;;
    esac
    if APP_BINARY_DIRECTORY= sh "$builder" "$configuration" >/dev/null 2>&1; then
        echo "$product bundler accepted an explicitly empty binary directory" >&2; exit 1
    fi
    if sh "$validator" "$bundle" "$binary_directory/$other" "$configuration" >/dev/null 2>&1; then
        echo "$product validator accepted another product's executable" >&2; exit 1
    fi
    if sh "$validator" "$bundle" "$binary_directory/$product" "$wrong_configuration" >/dev/null 2>&1; then
        echo "$product validator accepted the wrong build configuration" >&2; exit 1
    fi
done
echo "Both Drawing app bundles match their exact build inputs; swapped sources/configurations refused"
