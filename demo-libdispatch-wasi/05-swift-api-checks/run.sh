#!/bin/bash
# Build libdispatch with the Swift overlay, compile demo.swift, and run its
# 11 checks. See README.md.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
parse_common_args "$@"
check_prerequisites swift
find_wasmkit
ensure_libdispatch swift
compile_swift "$BUILD_ROOT/05-swift-api-checks.wasm" "$EXAMPLES_DIR/05-swift-api-checks/demo.swift"
run_example "$BUILD_ROOT/05-swift-api-checks.wasm" "ALL 11 CHECKS PASSED"
