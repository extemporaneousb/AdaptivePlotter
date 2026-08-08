#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
source_bundle=${1:-"$project_root/.build/AdaptivePlotter.app"}
validator="$project_root/Scripts/validate_local_app_bundle.sh"

if [ ! -d "$source_bundle" ]; then
    echo "AdaptivePlotter app bundle is missing: $source_bundle" >&2
    exit 1
fi

for forbidden_key in NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription; do
    if /usr/libexec/PlistBuddy \
        -c "Print :$forbidden_key" \
        "$source_bundle/Contents/Info.plist" >/dev/null 2>&1
    then
        echo "camera-only bundle unexpectedly declares $forbidden_key" >&2
        exit 1
    fi
done

test_root=$(mktemp -d "$project_root/.build/.AdaptivePlotter-validation.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

unsigned_bundle="$test_root/Unsigned.app"
mkdir -p "$unsigned_bundle/Contents/MacOS"
install -m 755 \
    "$source_bundle/Contents/MacOS/AdaptivePlotter" \
    "$unsigned_bundle/Contents/MacOS/AdaptivePlotter"
install -m 644 \
    "$source_bundle/Contents/Info.plist" \
    "$unsigned_bundle/Contents/Info.plist"
/usr/bin/codesign --remove-signature "$unsigned_bundle"

if sh "$validator" "$unsigned_bundle" >/dev/null 2>&1; then
    echo "bundle validation accepted an unsigned bundle" >&2
    exit 1
fi

tampered_bundle="$test_root/Tampered.app"
cp -R "$source_bundle" "$tampered_bundle"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' \
    "$tampered_bundle/Contents/Info.plist"

if sh "$validator" "$tampered_bundle" >/dev/null 2>&1; then
    echo "bundle validation accepted a bundle with a tampered Info.plist" >&2
    exit 1
fi

microphone_bundle="$test_root/Microphone.app"
cp -R "$source_bundle" "$microphone_bundle"
/usr/libexec/PlistBuddy \
    -c 'Add :NSMicrophoneUsageDescription string Unexpected' \
    "$microphone_bundle/Contents/Info.plist"
if microphone_result=$(sh "$validator" "$microphone_bundle" 2>&1); then
    echo "bundle validation accepted a microphone permission declaration" >&2
    exit 1
fi
if ! printf '%s\n' "$microphone_result" \
    | grep -Fq 'unexpected NSMicrophoneUsageDescription'
then
    printf '%s\n' "$microphone_result" >&2
    echo "bundle validator did not identify the microphone permission" >&2
    exit 1
fi

speech_bundle="$test_root/SpeechRecognition.app"
cp -R "$source_bundle" "$speech_bundle"
/usr/libexec/PlistBuddy \
    -c 'Add :NSSpeechRecognitionUsageDescription string Unexpected' \
    "$speech_bundle/Contents/Info.plist"
if speech_result=$(sh "$validator" "$speech_bundle" 2>&1); then
    echo "bundle validation accepted a speech-recognition permission declaration" >&2
    exit 1
fi
if ! printf '%s\n' "$speech_result" \
    | grep -Fq 'unexpected NSSpeechRecognitionUsageDescription'
then
    printf '%s\n' "$speech_result" >&2
    echo "bundle validator did not identify the speech-recognition permission" >&2
    exit 1
fi

signature_details=$(/usr/bin/codesign -d --verbose=4 "$source_bundle" 2>&1)
signature_requirement=$(/usr/bin/codesign -d -r- "$source_bundle" 2>&1)
if printf '%s\n' "$signature_details" | grep -Fqx 'Signature=adhoc'; then
    if ! printf '%s\n' "$signature_requirement" \
        | grep -Eq '^# designated => cdhash H"[[:xdigit:]]{40}"$'
    then
        printf '%s\n' "$signature_requirement" >&2
        echo "ad-hoc bundle lost its content-bound designated requirement" >&2
        exit 1
    fi
elif ! printf '%s\n' "$signature_requirement" \
    | grep -Fq 'identifier "com.bullard.AdaptivePlotter"'
then
    printf '%s\n' "$signature_requirement" >&2
    echo "identity-signed bundle lost its stable designated requirement" >&2
    exit 1
fi

echo "AdaptivePlotter app-bundle negative validation passed"
