#!/bin/sh
set -eu

# Guard durable capabilities and architecture. Completed migration names and
# ordinary technical vocabulary do not belong here.
forbidden_network_capability='URLSession|URLRequest|NWConnection|NWListener'
forbidden_child_capability='Process[[:space:]]*\('
approved_artist_client='Sources/PortraitArtists/SwiftSketchClient.swift'

if rg -n --glob '*.swift' "$forbidden_network_capability" Sources; then
    echo "network capability is outside the local application contract" >&2
    exit 1
fi

if rg -n --glob '*.swift' --glob "!$approved_artist_client" "$forbidden_child_capability" Sources; then
    echo "unapproved child-process capability is outside the local application contract" >&2
    exit 1
fi

# One reviewed artist client may invoke its configured local CPU worker and the
# fixed local RSS observer. Bind the entire implementation so new subprocess
# roles, target/argument changes or indirect invocation edits require re-review.
# This is not a directory, target, basename or generic Process exemption.
# Update this fingerprint only after deliberate client/guard review and all
# required checks. Never automatically refresh it from the current source hash.
if [ -f "$approved_artist_client" ]; then
    reviewed_client_sha256='60e2d45fd7d03885487f4f7054f9f631e281c05e67af6f6509fc1e2438312499'
    actual_client_sha256=$(shasum -a 256 "$approved_artist_client" | awk '{print $1}')
    constructor_count=$(rg -c "$forbidden_child_capability" "$approved_artist_client" || true)
    if [ "$actual_client_sha256" != "$reviewed_client_sha256" ] || [ "$constructor_count" != 2 ] ||
        ! rg -Fq 'process.executableURL = config.pythonExecutable' "$approved_artist_client" ||
        ! rg -Fq 'process.arguments = [config.workerScript.path, "--request", requestFile.path,' "$approved_artist_client" ||
        ! rg -Fq '"--manifest", config.modelManifest.path, "--output", output.path]' "$approved_artist_client" ||
        ! rg -Fq 'process.executableURL = URL(fileURLWithPath: "/bin/ps")' "$approved_artist_client" ||
        ! rg -Fq 'process.arguments = ["-o", "rss=", "-p", String(pid)]' "$approved_artist_client"; then
        echo "reviewed SwiftSketch local worker/RSS subprocess seams changed; explicit guard re-review required" >&2
        exit 1
    fi
fi

if find Sources -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' \) -print | grep -q .; then
    echo "non-Swift live product source found" >&2
    exit 1
fi
