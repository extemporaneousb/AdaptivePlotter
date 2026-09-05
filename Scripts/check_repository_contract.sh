#!/bin/sh
set -eu

# Guard durable capabilities and architecture. Completed migration names and
# ordinary technical vocabulary do not belong here.
forbidden_product_capability='URLSession|URLRequest|NWConnection|NWListener|Process[[:space:]]*\('

if rg -n --glob '*.swift' "$forbidden_product_capability" Sources; then
    echo "network or child-process capability is outside the single local application contract" >&2
    exit 1
fi

if find Sources -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' \) -print | grep -q .; then
    echo "non-Swift live product source found" >&2
    exit 1
fi
