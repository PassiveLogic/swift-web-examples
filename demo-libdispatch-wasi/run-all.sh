#!/bin/bash
# Run every libdispatch on WASI example. Set LIBDISPATCH_SRC first.
#   --wasmtime  also run the command line examples with wasmtime
#   --clean     delete the shared build folder first
set -euo pipefail
cd "$(dirname "$0")"

args=()
for arg in "$@"; do
  case "$arg" in
    --wasmtime) args+=(--wasmtime) ;;
    --clean) rm -rf .build ;;
    *) echo "Usage: $0 [--wasmtime] [--clean]" >&2; exit 2 ;;
  esac
done

for example in 01-c-hello 02-swift-hello 03-swift-timers-and-waits \
               04-c-api-checks 05-swift-api-checks; do
  "./$example/run.sh" ${args[@]+"${args[@]}"}
done

# The browser examples only build here. Run one with its build.sh --serve,
# then open http://localhost:8080 in a browser.
./06-browser-host-loop/build.sh
./07-elementary-ui-single-threaded-demo/build.sh

echo
echo "Done. The command line examples passed, and the browser examples built."
