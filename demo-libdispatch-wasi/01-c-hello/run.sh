#!/bin/bash
# Build libdispatch, compile main.c, and run it. See README.md.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
parse_common_args "$@"
check_prerequisites c
find_wasmkit
ensure_libdispatch c
compile_c "$BUILD_ROOT/01-c-hello.wasm" "$EXAMPLES_DIR/01-c-hello/main.c"
run_example "$BUILD_ROOT/01-c-hello.wasm" "all blocks are done"
