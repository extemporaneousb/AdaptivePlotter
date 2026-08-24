#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: sh Scripts/check_episode_cutover.sh <PACKAGE-ID>" >&2
    exit 2
fi

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PYTHONDONTWRITEBYTECODE=1 exec "$project_root/.VE/bin/python" "$project_root/Scripts/check_episode_cutover.py" "$1"
