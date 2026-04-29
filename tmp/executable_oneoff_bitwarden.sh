#!/bin/sh
## Install Bitwarden CLI temporarily and open session


TMPDIR="${TMPDIR:-/tmp}/bw.$$"
trap 'rm -rf "${TMPDIR}"' EXIT INT TERM

touch "$TMPDIR/data.json"
export BITWARDENCLI_APPDATA_DIR="$TMPDIR"

if command -v bw > /dev/null 2>&1; then
    CMD=bw
else
    os="$(uname)"
    if [ "$os" = "Darwin" ]; then os=macos; fi
    wget -qO "$TMPDIR/bw.zip" "https://bitwarden.com/download/?app=cli&platform=$os"
    unzip -qq "$TMPDIR/bw.zip" -d "$TMPDIR"
    chmod +x "$TMPDIR/bw"
    CMD="$TMPDIR/bw"
fi

BW_SESSION="$("$CMD" login --raw)"
export BW_SESSION
"$CMD" "$@"
