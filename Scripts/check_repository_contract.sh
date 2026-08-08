#!/bin/sh
set -eu

forbidden_pattern='URLSession|localhost|127\\.0\\.0\\.1|PlotterBridge|BridgeProcessSupervisor|PlanInstruction|TranscriptReplay|OfflineRuntimePrototype'
removed_workflow_pattern='[Cc]alibrat|[Pp]reflight|[Rr]eadiness|[Rr]ehears|Use Voice|Practice Voice|Start Exploration|End Exploration|VoiceInteraction|VoiceActions|voiceListening|voiceInput|AVAudioEngine|SFSpeechRecognizer|NSSpeechRecognitionUsageDescription|NSMicrophoneUsageDescription|Activate Motion Guard|Deactivate Motion Guard'

if rg -n --glob '*.swift' "$forbidden_pattern" Sources Tests; then
    echo "forbidden live/compatibility surface found" >&2
    exit 1
fi

if rg -n --glob '*.swift' --glob '*.plist' "$removed_workflow_pattern" Sources Tests Resources; then
    echo "removed learning, speech-input, or visible motion-arming surface found" >&2
    exit 1
fi

for removed_path in \
    Sources/PlotterApp/ExplorationPresentation.swift \
    Sources/PlotterApp/PreflightCalibrationView.swift \
    Sources/PlotterRuntime/ExplorationSession.swift \
    Sources/PlotterRuntime/PreflightCalibration.swift \
    Sources/PlotterRuntime/VoiceInteraction.swift \
    Tests/PlotterAppTests/ExplorationFlowCoordinatorTests.swift \
    Tests/PlotterAppTests/PreflightCalibrationPresentationTests.swift \
    Tests/PlotterRuntimeTests/ExplorationSessionTests.swift \
    Tests/PlotterRuntimeTests/PreflightCalibrationTests.swift \
    Tests/PlotterRuntimeTests/VoiceInteractionTests.swift
do
    if [ -e "$removed_path" ]; then
        echo "removed compatibility path returned: $removed_path" >&2
        exit 1
    fi
done

if find Sources -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' \) -print | grep -q .; then
    echo "non-Swift live product source found" >&2
    exit 1
fi

swift package describe >/dev/null
