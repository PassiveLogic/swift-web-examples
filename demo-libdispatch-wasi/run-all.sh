#!/bin/bash
# Walk through the libdispatch on WASI examples one at a time.
#
#   ./run-all.sh              pause before and after each example
#   ./run-all.sh --no-pause   run every example without pausing (smoke test)
#
# Options:
#   --no-pause  do not pause. The browser examples only build.
#   --wasmtime  also run the command line examples with wasmtime
#   --clean     delete the build folders first
#
# Before the first example, the script checks the tools, downloads or updates
# libdispatch (unless LIBDISPATCH_SRC is set), and builds it. Without a
# terminal, the script does not pause.
set -euo pipefail
cd "$(dirname "$0")"

usage() {
  sed -n '2,14p' ./run-all.sh | sed 's/^# \{0,1\}//'
}

pause=1
args=()
for arg in "$@"; do
  case "$arg" in
    --no-pause) pause=0 ;;
    --wasmtime) args+=(--wasmtime) ;;
    --clean) rm -rf .build 06-browser-host-loop/.build 07-elementary-ui-single-threaded-demo/.build ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done
[ -t 0 ] || pause=0

source ./common.sh

# The examples, in order: folder, kind, and a short description.
examples=(
  "01-c-hello|cli|C: three blocks on a serial queue, then a summary on the main queue."
  "02-swift-hello|cli|Swift: the same program as 01, with import Dispatch."
  "03-swift-timers-and-waits|cli|Swift: how timers and blocking waits behave with one thread."
  "04-c-api-checks|cli|C: 12 checks of the libdispatch C API, each prints PASS or FAIL."
  "05-swift-api-checks|cli|Swift: the same checks with the Swift API (11, Swift has no dispatch_once)."
  "06-browser-host-loop|browser|Browser: the page event loop drives Dispatch through the host event loop SPI."
  "07-elementary-ui-single-threaded-demo|browser|Browser: an all-Swift UI that runs one Dispatch drain step at a time."
)

# Read one key line from the terminal. Return it in $reply.
ask() {
  reply=""
  [ "$pause" = 1 ] || return 0
  read -r -p "$1" reply </dev/tty || reply=""
}

server_pid=""
stop_server() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=""
  fi
}
trap stop_server EXIT

# Serve a browser example until the user presses Enter.
serve_example() {
  local dir="$1"
  if python3 - <<'EOF' 2>/dev/null
import socket
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 8080))
EOF
  then
    python3 -m http.server 8080 --bind 127.0.0.1 --directory "$dir" >/dev/null 2>&1 &
    server_pid=$!
    # Wait up to 5 s until the server accepts connections.
    local tries=0
    until (exec 3<>/dev/tcp/127.0.0.1/8080) 2>/dev/null; do
      tries=$((tries + 1))
      if [ "$tries" -ge 50 ]; then
        echo "    The web server did not start. Run $dir/build.sh --serve later."
        stop_server
        return 0
      fi
      sleep 0.1
    done
    echo
    echo "    Open http://127.0.0.1:8080 in a browser. See $dir/README.md for what to try."
    ask "    Press Enter to stop the server and continue. "
    stop_server
  else
    echo "    Port 8080 is in use, so the page is not served. Run $dir/build.sh --serve later."
  fi
}

# Step 1: Check the tools, get libdispatch, and build both kinds of
# libdispatch once, so that the examples start quickly.
check_prerequisites swift
export LIBDISPATCH_SRC
ensure_libdispatch c
ensure_libdispatch swift

total=${#examples[@]}
passed=()
failed=()
skipped=()

# Step 2: Run the examples.
i=0
for entry in "${examples[@]}"; do
  i=$((i + 1))
  IFS='|' read -r name kind about <<<"$entry"
  echo
  echo "================================================================"
  echo "Example $i of $total: $name"
  echo "  $about"
  echo "  Code and notes: $name/README.md"
  echo "================================================================"
  ask "Press Enter to run it, s to skip, or q to quit: "
  case "$reply" in
    q|Q) echo "Stopped."; break ;;
    s|S) skipped+=("$name"); continue ;;
  esac

  if [ "$kind" = cli ]; then
    if "./$name/run.sh" ${args[@]+"${args[@]}"}; then passed+=("$name"); else failed+=("$name"); fi
  else
    if "./$name/build.sh"; then
      passed+=("$name (built)")
      [ "$pause" = 1 ] && serve_example "$name"
    else
      failed+=("$name")
    fi
  fi
  if [ "$i" -lt "$total" ]; then
    ask "Press Enter for the next example, or q to quit: "
    case "$reply" in q|Q) echo "Stopped."; break ;; esac
  fi
done

# Step 3: Print a summary.
echo
echo "Summary:"
[ ${#passed[@]} -eq 0 ] || printf '  passed:  %s\n' "${passed[@]}"
[ ${#skipped[@]} -eq 0 ] || printf '  skipped: %s\n' "${skipped[@]}"
[ ${#failed[@]} -eq 0 ] || printf '  FAILED:  %s\n' "${failed[@]}"
if [ ${#failed[@]} -ne 0 ]; then
  exit 1
fi
if [ ${#passed[@]} -eq "$total" ]; then
  echo
  echo "Done. The command line examples passed, and the browser examples built."
fi
