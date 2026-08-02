#!/bin/sh
set -eu

forbidden_pattern='URLSession|localhost|127\\.0\\.0\\.1|PlotterBridge|BridgeProcessSupervisor|PlanInstruction'

if rg -n --glob '*.swift' "$forbidden_pattern" Sources Tests; then
    echo "forbidden live/compatibility surface found" >&2
    exit 1
fi

if find Sources -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' \) -print | grep -q .; then
    echo "non-Swift live product source found" >&2
    exit 1
fi

swift package describe >/dev/null
