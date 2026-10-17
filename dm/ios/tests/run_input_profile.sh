#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCES=${1:-"$HERE/../Sources"}
if [ ! -f "$SOURCES/dm_measurement.h" ] || [ ! -f "$SOURCES/dm_input_tick.h" ]; then
 echo 'INPUT_PROFILE_CONTRACT unavailable: source predates1705 input/profile guards'
 exit 1
fi
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/d2r-input-profile.XXXXXX")
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM
xcrun clang -fobjc-arc -I"$SOURCES" "$HERE/t_input_profile.m" -framework Foundation -o "$TEMP/check"
"$TEMP/check" "$TEMP/documents"
