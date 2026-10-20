# Shared settings and helpers for the libdispatch on WASI examples.
# Each example script sources this file. It does not run anything itself.
#
# Environment variables (all optional except LIBDISPATCH_SRC):
#
#   LIBDISPATCH_SRC  A libdispatch source tree with the cooperative WASI
#                    backend (src/event/event_wasi.c).
#   SWIFT_TOOLCHAIN  Host Swift toolchain (.xctoolchain).
#   WASM_SDK         The wasm32-unknown-wasip1 folder of a Swift SDK for WASI.
#   WASMKIT          The WasmKit command line tool. If you do not set it, the
#                    scripts look for WasmKit 0.3.0 or newer.
#   WASMTIME         The wasmtime command line tool.

SWIFT_TOOLCHAIN="${SWIFT_TOOLCHAIN:-$HOME/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain}"
SWIFT_SDK_ID="${SWIFT_SDK_ID:-swift-6.3.1-RELEASE_wasm}"
WASM_SDK="${WASM_SDK:-$HOME/Library/org.swift.swiftpm/swift-sdks/$SWIFT_SDK_ID.artifactbundle/$SWIFT_SDK_ID/wasm32-unknown-wasip1}"
LIBDISPATCH_SRC="${LIBDISPATCH_SRC:-}"
WASMKIT="${WASMKIT:-}"
WASMTIME="${WASMTIME:-$(command -v wasmtime || echo wasmtime)}"

# The examples folder (the folder that holds this file) and its build folder.
EXAMPLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="$EXAMPLES_DIR/.build"

TARGET=wasm32-unknown-wasip1
CLANG="$SWIFT_TOOLCHAIN/usr/bin/clang"
SWIFTC="$SWIFT_TOOLCHAIN/usr/bin/swiftc"
SWIFT="$SWIFT_TOOLCHAIN/usr/bin/swift"
SYSROOT="$WASM_SDK/WASI.sdk"
SWIFT_STATIC="$WASM_SDK/swift.xctoolchain/usr/lib/swift_static"
WASM_CLANG_RESOURCES="$WASM_SDK/swift.xctoolchain/usr/lib/clang"
BUILTINS="$WASM_CLANG_RESOURCES/lib/wasip1/libclang_rt.builtins-wasm32.a"

# The stage folders that build_libdispatch installs into.
C_STAGE="$BUILD_ROOT/stage-c/usr"
SWIFT_STAGE="$BUILD_ROOT/stage-swift/usr"
SWIFT_LIBS="$SWIFT_STAGE/lib/swift_static"

absolute_dir() {
  if [ -d "$1" ]; then (cd "$1" && pwd); else echo "$1"; fi
}

# =============== Helpers ==============

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

step() {
  echo
  echo "==> $*"
}

# The time now, in seconds, with fractions. Perl is part of macOS.
now() {
  perl -MTime::HiRes=time -e 'printf "%.2f", time'
}

# Seconds since a time from now(), with one decimal place.
since() {
  perl -MTime::HiRes=time -e 'printf "%.1f", time - $ARGV[0]' "$1"
}

# Run a command and print how long it took.
timed() {
  local label="$1"
  shift
  local start
  start="$(now)"
  "$@"
  echo "    ($label took $(since "$start") s)"
}

# Run a command, send its output to a log file, and print how long it took.
# If the command fails, show the end of the log and stop.
#   $1  label for messages
#   $2  log file
#   rest: the command
logged() {
  local label="$1" log="$2"
  shift 2
  local start
  start="$(now)"
  if ! "$@" >"$log" 2>&1; then
    tail -n 40 "$log"
    fail "$label failed. See $log"
  fi
  echo "    ($label took $(since "$start") s, log: ${log#"$EXAMPLES_DIR"/})"
}

# Check that a file or folder exists. Print a hint if it does not.
need_path() {
  local path="$1" hint="$2"
  [ -e "$path" ] || fail "Not found: $path
       $hint"
}

# Check that CMake is 3.31 or newer. That is the first CMake that knows WASI.
check_cmake_version() {
  local version major minor
  version="$(cmake --version | head -n 1 | awk '{print $3}')"
  major="${version%%.*}"
  minor="${version#*.}"
  minor="${minor%%.*}"
  if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 31 ]; }; then
    fail "CMake 3.31 or newer is necessary. Found $version."
  fi
}

# Print the version of a WasmKit command, or nothing if it does not run.
wasmkit_version() {
  "$1" --version 2>/dev/null | tail -n 1 | tr -d '[:space:]'
}

# Succeed if version $1 is the same as or newer than version $2.
version_at_least() {
  local IFS=.
  local -a have=($1) want=($2)
  local i
  for i in 0 1 2; do
    local h="${have[$i]:-0}" w="${want[$i]:-0}"
    [[ "$h" =~ ^[0-9]+$ ]] || return 1
    if [ "$h" -gt "$w" ]; then return 0; fi
    if [ "$h" -lt "$w" ]; then return 1; fi
  done
  return 0
}

# WasmKit 0.3.0 is the first release with poll_oneoff. libdispatch uses
# poll_oneoff (through nanosleep) to sleep until the next timer.
# The Swift 6.3 toolchains ship WasmKit 0.1.6. It does not have poll_oneoff.
# With it, an example still passes, but each sleep becomes a busy loop, and
# WasmKit prints '"poll_oneoff" not implemented yet' many times.
MIN_WASMKIT=0.3.0

# Set WASMKIT and WASMKIT_VERSION.
# Use WASMKIT if it is set. If not, try wasmkit on PATH, then the wasmkit in
# each installed Swift toolchain. Use the first one that is new enough.
find_wasmkit() {
  local candidate version first="" first_version=""
  if [ -n "$WASMKIT" ]; then
    command -v "$WASMKIT" >/dev/null || fail "WASMKIT is not a program: $WASMKIT"
    WASMKIT="$(command -v "$WASMKIT")"
    WASMKIT_VERSION="$(wasmkit_version "$WASMKIT" || true)"
  else
    local -a candidates=()
    if command -v wasmkit >/dev/null; then
      candidates+=("$(command -v wasmkit)")
    fi
    candidates+=("$SWIFT_TOOLCHAIN/usr/bin/wasmkit")
    for candidate in "$HOME"/Library/Developer/Toolchains/*.xctoolchain/usr/bin/wasmkit \
                     /Library/Developer/Toolchains/*.xctoolchain/usr/bin/wasmkit; do
      [ -x "$candidate" ] && candidates+=("$candidate")
    done
    for candidate in "${candidates[@]}"; do
      [ -x "$candidate" ] || continue
      version="$(wasmkit_version "$candidate" || true)"
      [ -n "$version" ] || continue
      if [ -z "$first" ]; then
        first="$candidate"
        first_version="$version"
      fi
      if version_at_least "$version" "$MIN_WASMKIT"; then
        WASMKIT="$candidate"
        WASMKIT_VERSION="$version"
        return
      fi
    done
    [ -n "$first" ] || fail "WasmKit not found. Install a Swift toolchain that has it, or set WASMKIT."
    WASMKIT="$first"
    WASMKIT_VERSION="$first_version"
  fi
  if ! version_at_least "$WASMKIT_VERSION" "$MIN_WASMKIT"; then
    echo "WARNING: WasmKit $WASMKIT_VERSION has no poll_oneoff. Version $MIN_WASMKIT or newer"
    echo "         is better. The demo can still pass, but sleeps become busy loops"
    echo "         and WasmKit prints '\"poll_oneoff\" not implemented yet' many times."
    echo "         Set WASMKIT to a newer wasmkit to fix this."
  fi
}

# =============== Build libdispatch ==============

# Configure, build, and install libdispatch into a stage folder.
#   $1  name of the build (c or swift)
#   $2  YES to build the Swift overlay, NO for the C library only
build_libdispatch() {
  local name="$1" enable_swift="$2"
  local build_dir="$BUILD_ROOT/libdispatch-$name"
  local stage_dir="$BUILD_ROOT/stage-$name"

  # A CMake build folder belongs to one source tree. Start over if the
  # source tree changed since the last run.
  if [ -f "$build_dir/CMakeCache.txt" ] &&
     ! grep -qxF "CMAKE_HOME_DIRECTORY:INTERNAL=$LIBDISPATCH_SRC" "$build_dir/CMakeCache.txt"; then
    echo "LIBDISPATCH_SRC changed. Deleting $build_dir."
    rm -rf "$build_dir" "$stage_dir"
  fi

  # These settings tell CMake to cross-compile for WASI with the clang in the
  # Swift toolchain and the WASI sysroot in the SDK. No toolchain file is
  # necessary. CMake cannot link test programs for WASI, so its checks build
  # static libraries instead (CMAKE_TRY_COMPILE_TARGET_TYPE).
  local cmake_args=(
    -S "$LIBDISPATCH_SRC" -B "$build_dir" -G Ninja
    -DCMAKE_SYSTEM_NAME=WASI
    -DCMAKE_SYSTEM_PROCESSOR=wasm32
    -DCMAKE_SYSROOT="$SYSROOT"
    -DCMAKE_C_COMPILER="$CLANG"
    -DCMAKE_CXX_COMPILER="$SWIFT_TOOLCHAIN/usr/bin/clang++"
    -DCMAKE_AR="$SWIFT_TOOLCHAIN/usr/bin/llvm-ar"
    -DCMAKE_RANLIB="$SWIFT_TOOLCHAIN/usr/bin/llvm-ranlib"
    -DCMAKE_C_COMPILER_TARGET="$TARGET"
    -DCMAKE_CXX_COMPILER_TARGET="$TARGET"
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
    -DBUILD_TESTING=OFF
    -DCMAKE_BUILD_TYPE=Release
    -DENABLE_SWIFT="$enable_swift"
  )
  if [ "$enable_swift" = YES ]; then
    cmake_args+=(
      -DCMAKE_Swift_COMPILER="$SWIFTC"
      -DCMAKE_Swift_COMPILER_TARGET="$TARGET"
      "-DCMAKE_Swift_FLAGS=-sdk $SYSROOT -resource-dir $SWIFT_STATIC"
      -Ddispatch_MODULE_TRIPLE="$TARGET"
      -Ddispatch_ARCH=wasm32
      -Ddispatch_PLATFORM=wasi
    )
  fi

  step "Configure libdispatch ($name) in ${build_dir#"$EXAMPLES_DIR"/}"
  logged configure "$BUILD_ROOT/configure-$name.log" cmake "${cmake_args[@]}"

  step "Build libdispatch ($name)"
  logged build "$BUILD_ROOT/build-$name.log" ninja -C "$build_dir"

  step "Install libdispatch ($name) into ${stage_dir#"$EXAMPLES_DIR"/}"
  rm -rf "$stage_dir"
  logged install "$BUILD_ROOT/install-$name.log" \
    env DESTDIR="$stage_dir" cmake --install "$build_dir" --prefix /usr
}

# =============== Prerequisites ==============

# Check the tools and folders that every example needs.
#   $1  "swift" when the example needs the Swift overlay, else "c"
check_prerequisites() {
  local kind="$1"
  step "Check prerequisites"
  command -v cmake >/dev/null || fail "cmake is not on PATH. Install CMake 3.31 or newer."
  check_cmake_version
  command -v ninja >/dev/null || fail "ninja is not on PATH. Try: brew install ninja"
  need_path "$CLANG" "Install a Swift toolchain, or set SWIFT_TOOLCHAIN to one."
  need_path "$SYSROOT" "Install the Swift SDK for WASI, or set WASM_SDK to its wasm32-unknown-wasip1 folder."
  need_path "$BUILTINS" "WASM_SDK does not hold the compiler-rt builtins for wasip1."
  [ -n "$LIBDISPATCH_SRC" ] || fail "Set LIBDISPATCH_SRC to a libdispatch source tree with the
       cooperative WASI backend (src/event/event_wasi.c)."
  LIBDISPATCH_SRC="$(absolute_dir "$LIBDISPATCH_SRC")"
  need_path "$LIBDISPATCH_SRC/src/event/event_wasi.c" \
    "LIBDISPATCH_SRC has no cooperative WASI backend (src/event/event_wasi.c)."
  if [ "$kind" = swift ]; then
    need_path "$SWIFTC" "The Swift toolchain has no swiftc."
    need_path "$SWIFT_STATIC" "WASM_SDK has no static Swift runtime (swift_static)."
    grep -q 'os(WASI)' "$LIBDISPATCH_SRC/src/swift/Source.swift" 2>/dev/null ||
      fail "LIBDISPATCH_SRC has no Swift overlay support for WASI."
  fi
  mkdir -p "$BUILD_ROOT"
}

# Configure, build, and install libdispatch. The first run compiles the
# library. A later run configures again, but ninja compiles only what
# changed. Then the stage folder is installed again.
#   $1  c or swift
ensure_libdispatch() {
  if [ "$1" = swift ]; then build_libdispatch swift YES; else build_libdispatch c NO; fi
}

# =============== Compile ==============

# Compile C sources to a wasm command module.
#   $1  output .wasm file
#   rest: the C sources
compile_c() {
  local out="$1"
  shift
  step "Compile ${out#"$EXAMPLES_DIR"/}"
  # libdispatch for WASI uses the wasi-libc emulation libraries for signals,
  # mmap, and getpid. The program also needs the BlocksRuntime library.
  # The host clang looks for the wasm32 builtins in its own folder, and they
  # are not there. So -nodefaultlibs turns off the default libraries, and the
  # command names libc and the builtins archive from the SDK.
  timed compile "$CLANG" --target="$TARGET" --sysroot="$SYSROOT" \
    -O2 -fblocks -Wall -Werror \
    -I"$C_STAGE/include" -L"$C_STAGE/lib" \
    "$@" -o "$out" \
    -ldispatch -lBlocksRuntime \
    -lwasi-emulated-signal -lwasi-emulated-mman -lwasi-emulated-getpid \
    -nodefaultlibs -lc "$BUILTINS"
}

# Compile Swift sources to a wasm command module.
#   $1  output .wasm file
#   rest: the Swift sources
compile_swift() {
  local out="$1"
  shift
  step "Compile ${out#"$EXAMPLES_DIR"/}"
  # The Swift overlay installs into lib/swift_static, the same layout as the
  # static Swift runtime. The Dispatch module names its libraries for the
  # linker, so -I and -L are enough. The linker needs the clang resource
  # folder of the SDK, because the host toolchain has no wasm32 builtins.
  timed compile "$SWIFTC" -target "$TARGET" \
    -sdk "$SYSROOT" -resource-dir "$SWIFT_STATIC" -static-stdlib -O \
    -I "$SWIFT_LIBS" -I "$SWIFT_LIBS/wasi" -L "$SWIFT_LIBS/wasi" \
    -Xclang-linker -resource-dir -Xclang-linker "$WASM_CLANG_RESOURCES" \
    "$@" -o "$out"
}

# =============== Run ==============

# Run a wasm file with WasmKit, and with wasmtime when RUN_WASMTIME=1.
# Stop with an error if the exit status is not 0, if a line has "FAIL", or
# if the expected line is missing.
#   $1  the wasm file
#   $2  a line that the output must contain
run_example() {
  local wasm="$1" expected="$2"
  local runtimes=("wasmkit")
  [ "${RUN_WASMTIME:-0}" = 1 ] && runtimes+=("wasmtime")
  local runtime
  for runtime in "${runtimes[@]}"; do
    local log="$BUILD_ROOT/run-$(basename "$wasm" .wasm)-$runtime.log"
    local cmd=("$WASMKIT" run "$wasm")
    [ "$runtime" = wasmtime ] && cmd=("$WASMTIME" run "$wasm")
    step "Run ${wasm#"$EXAMPLES_DIR"/} with $runtime"
    local status=0 start
    start="$(now)"
    "${cmd[@]}" >"$log" 2>&1 || status=$?
    # WasmKit 0.1.6 prints '"poll_oneoff" not implemented yet' for each
    # sleep, sometimes in the middle of a program line. Remove that text.
    local output="$log.clean"
    sed 's/"poll_oneoff" not implemented yet//g' "$log" | grep -v '^[[:space:]]*$' >"$output" || true
    sed 's/^/    | /' "$output"
    echo "    (run took $(since "$start") s, exit status $status)"
    [ "$status" -eq 0 ] || fail "$runtime: exit status $status. Log: $log"
    ! grep -q 'FAIL' "$output" || fail "$runtime: the output has a FAIL line. Log: $log"
    grep -qxF "$expected" "$output" || fail "$runtime: missing the line \"$expected\". Log: $log"
    echo "    OK"
  done
}

# Build a browser example with the PackageToJS plugin of JavaScriptKit.
#   $1  the example folder
#   rest: --serve to also serve the folder on http://localhost:8080 (on this
#         machine only), --clean to delete the build folders first
build_browser_example() {
  local dir="$1"
  shift
  local serve=0 arg
  for arg in "$@"; do
    case "$arg" in
      --serve) serve=1 ;;
      --clean) rm -rf "$BUILD_ROOT" "$dir/.build" ;;
      *) echo "Usage: $0 [--serve] [--clean]" >&2; exit 2 ;;
    esac
  done
  check_prerequisites swift
  ensure_libdispatch swift

  cd "$dir"
  step "Build ${dir#"$EXAMPLES_DIR"/} for the browser"
  # Package.swift reads this variable to find the Dispatch module.
  export LIBDISPATCH_SWIFT_LIBS="$SWIFT_LIBS"
  timed build "$SWIFT" package --swift-sdk "$SWIFT_SDK_ID" js --use-cdn

  if [ "$serve" = 1 ]; then
    step "Serve on http://localhost:8080"
    python3 -m http.server 8080 --bind 127.0.0.1
  fi
}

# Parse the options that every command line example takes.
parse_common_args() {
  RUN_WASMTIME="${RUN_WASMTIME:-0}"
  local arg
  for arg in "$@"; do
    case "$arg" in
      --wasmtime) RUN_WASMTIME=1 ;;
      --clean) rm -rf "$BUILD_ROOT" ;;
      -h|--help)
        echo "Usage: $0 [--wasmtime] [--clean]"
        echo "  --wasmtime  also run the example with wasmtime"
        echo "  --clean     delete the shared build folder first"
        echo "Set LIBDISPATCH_SRC to a libdispatch tree with the WASI port."
        exit 0 ;;
      *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
  done
}
