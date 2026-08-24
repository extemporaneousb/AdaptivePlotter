#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PYTHONDONTWRITEBYTECODE=1 "$project_root/.VE/bin/python" "$project_root/Scripts/check_episode_inventory.py"
sh -n "$project_root/Scripts/check_episode_cutover.sh"
PYTHONDONTWRITEBYTECODE=1 "$project_root/.VE/bin/python" "$project_root/Scripts/check_episode_cutover.py" --validate-manifest
