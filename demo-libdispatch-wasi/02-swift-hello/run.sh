#!/bin/bash
# Build libdispatch with the Swift overlay, compile main.swift, and run it.
# See README.md.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
parse_common_args "$@"
check_prerequisites swift
find_wasmkit
ensure_libdispatch swift
compile_swift "$BUILD_ROOT/02-swift-hello.wasm" "$EXAMPLES_DIR/02-swift-hello/main.swift"
run_example "$BUILD_ROOT/02-swift-hello.wasm" "all closures are done"
