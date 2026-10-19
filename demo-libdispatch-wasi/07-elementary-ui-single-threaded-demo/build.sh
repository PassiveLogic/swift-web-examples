#!/bin/bash
# Build libdispatch with the Swift overlay, then build this package for the
# browser with the PackageToJS plugin of JavaScriptKit. See README.md.
#   --serve  also start a local web server on port 8080
set -euo pipefail
source "$(dirname "$0")/../common.sh"
SERVE=0
for arg in "$@"; do
  case "$arg" in
    --serve) SERVE=1 ;;
    --clean) rm -rf "$BUILD_ROOT" "$(dirname "$0")/.build" ;;
    *) echo "Usage: $0 [--serve] [--clean]" >&2; exit 2 ;;
  esac
done
check_prerequisites swift
ensure_libdispatch swift

cd "$(dirname "$0")"
step "Build the package for the browser"
export LIBDISPATCH_SWIFT_LIBS="$SWIFT_LIBS"
timed build "$SWIFT" package --swift-sdk "$SWIFT_SDK_ID" js --use-cdn

if [ "$SERVE" = 1 ]; then
  step "Serve on http://localhost:8080"
  python3 -m http.server 8080
fi
