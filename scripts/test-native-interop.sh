#!/usr/bin/env bash
# Real libzero + TUI/GUI interoperability. Only temporary test data is used.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
gui_dir="$(dirname -- "$script_dir")"
source "$gui_dir/tool/dev-env.sh"
export ZERO_BEAT_NATIVE_TEST=1
export ZERO_SYNC_BACKEND=gogit
export ZERO_BEAT_TUI_BINARY="$gui_dir/build/validation/zero-tui"
export LD_LIBRARY_PATH="$gui_dir/build${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
cd "$gui_dir/packages/zero_beat_rpc"
exec dart test --concurrency=1 "$@"
