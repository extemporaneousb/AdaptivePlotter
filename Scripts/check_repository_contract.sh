#!/bin/sh
set -eu

# Guard durable capabilities and architecture. Completed migration names and
# ordinary technical vocabulary do not belong here.
forbidden_product_capability='URLSession|URLRequest|NWConnection|NWListener|Process[[:space:]]*\('
speech_input_capability='import Speech|SFSpeechRecognizer|SFSpeechAudioBufferRecognitionRequest|AVAudioEngine|voiceListening|voiceInput'
speech_input_privacy='NSSpeechRecognitionUsageDescription|NSMicrophoneUsageDescription'

if rg -n --glob '*.swift' "$forbidden_product_capability" Sources; then
    echo "network or child-process capability is outside the single local application contract" >&2
    exit 1
fi

if rg -n --glob '*.swift' "$speech_input_capability" Sources Tests; then
    echo "speech-input capability is outside the button-input and output-only speech contract" >&2
    exit 1
fi

if rg -n --glob '*.plist' "$speech_input_privacy" Resources; then
    echo "speech-input or microphone privacy declaration returned without a product input workflow" >&2
    exit 1
fi

if find Sources -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' \) -print | grep -q .; then
    echo "non-Swift live product source found" >&2
    exit 1
fi
