#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
exec sh "$project_root/Scripts/build_drawing_app.sh" AdaptivePlotter "$@"
