#!/bin/bash
# Build libdispatch, compile demo.c, and run its 12 checks. See README.md.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
parse_common_args "$@"
check_prerequisites c
find_wasmkit
ensure_libdispatch c
compile_c "$BUILD_ROOT/04-c-api-checks.wasm" "$EXAMPLES_DIR/04-c-api-checks/demo.c"
run_example "$BUILD_ROOT/04-c-api-checks.wasm" "ALL 12 CHECKS PASSED"
