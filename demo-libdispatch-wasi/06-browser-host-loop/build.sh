#!/bin/bash
# Build libdispatch with the Swift overlay, then build this package for the
# browser. See README.md.
#   --serve  also serve the page on http://localhost:8080 (this machine only)
#   --clean  delete the build folders first
set -euo pipefail
source "$(dirname "$0")/../common.sh"
build_browser_example "$(cd "$(dirname "$0")" && pwd)" "$@"
