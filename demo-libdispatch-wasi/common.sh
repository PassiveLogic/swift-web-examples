# Shared settings and helpers for the libdispatch on WASI examples.
# Each example script sources this file. It does not run anything itself.
#
# Environment variables (all optional):
#
#   LIBDISPATCH_SRC  A local libdispatch source tree with the cooperative WASI
#                    backend (src/event/event_wasi.c). If you do not set it,
#                    the scripts download LIBDISPATCH_GIT_REF of
#                    LIBDISPATCH_GIT_URL into .build/libdispatch-src, and
#                    update that copy on each run.
#   LIBDISPATCH_GIT_URL  The libdispatch repository to download.
#   LIBDISPATCH_GIT_REF  The branch or tag to download.
#   SWIFT_TOOLCHAIN  Host Swift toolchain (.xctoolchain).
#   WASM_SDK         The wasm32-unknown-wasip1 folder of a Swift SDK for WASI.
#   WASMKIT          The WasmKit command line tool. If you do not set it, the
#                    scripts look for WasmKit 0.3.0 or newer.
#   WASMTIME         The wasmtime command line tool.

SWIFT_TOOLCHAIN="${SWIFT_TOOLCHAIN:-$HOME/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain}"
SWIFT_SDK_ID="${SWIFT_SDK_ID:-swift-6.3.1-RELEASE_wasm}"
WASM_SDK="${WASM_SDK:-$HOME/Library/org.swift.swiftpm/swift-sdks/$SWIFT_SDK_ID.artifactbundle/$SWIFT_SDK_ID/wasm32-unknown-wasip1}"
LIBDISPATCH_SRC="${LIBDISPATCH_SRC:-}"
# Upstream libdispatch does not have the WASI port yet. Until it does, the
# default is the branch that holds the full port, with the Swift overlay.
LIBDISPATCH_GIT_URL="${LIBDISPATCH_GIT_URL:-https://github.com/PassiveLogic/swift-corelibs-libdispatch.git}"
LIBDISPATCH_GIT_REF="${LIBDISPATCH_GIT_REF:-feat/scottm/libDispatchWasmV2}"
WASMKIT="${WASMKIT:-}"
WASMTIME="${WASMTIME:-$(command -v wasmtime || echo wasmtime)}"

# The defaults above are Swift 6.3.1. These are the official downloads for it,
# for the install hints. The Swift SDK must match the toolchain exactly.
DEFAULT_SWIFT_TOOLCHAIN="$HOME/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain"
WASM_SDK_URL="https://download.swift.org/swift-6.3.1-release/wasm-sdk/swift-6.3.1-RELEASE/swift-6.3.1-RELEASE_wasm.artifactbundle.tar.gz"
WASM_SDK_CHECKSUM="bd47baa20771f366d8beed7970afaa30742b2210097afd15f85427226d8f4cf2"

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

# Print the CMake version. Return 1 if it is older than 3.31, the first CMake
# that knows WASI.
cmake_version_ok() {
  local version major minor
  version="$(cmake --version | head -n 1 | awk '{print $3}')"
  echo "$version"
  major="${version%%.*}"
  minor="${version#*.}"
  minor="${minor%%.*}"
  [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 31 ]; }
}

# The prerequisites that are missing, as "what|install command" entries.
MISSING=()

# Note a missing prerequisite and the command that installs it.
#   $1  what is missing
#   $2  the install command
missing() {
  MISSING+=("$1|$2")
}

# If a prerequisite is missing, print each one with its install command, then
# stop. The scripts never install anything themselves.
report_missing() {
  [ ${#MISSING[@]} -eq 0 ] && return 0
  local entry
  echo >&2
  echo "ERROR: Install these prerequisites, then run the script again:" >&2
  for entry in "${MISSING[@]}"; do
    echo "  - ${entry%%|*}" >&2
    echo "      ${entry#*|}" >&2
  done
  if printf '%s\n' "${MISSING[@]}" | grep -q '|brew ' && ! command -v brew >/dev/null; then
    echo "  The brew commands need Homebrew. See https://brew.sh" >&2
  fi
  echo "  README.md lists every prerequisite, under Prerequisites." >&2
  exit 1
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
    [ -n "$first" ] || fail "WasmKit not found. Install it with one of these, or set WASMKIT:
         swiftly install main-snapshot   (WasmKit 0.3.0 or newer)
         swiftly install 6.3.1           (WasmKit 0.1.6, slower sleeps)"
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
  local kind="$1" version
  step "Check prerequisites"
  MISSING=()
  if ! command -v cmake >/dev/null; then
    missing "CMake 3.31 or newer" "brew install cmake"
  elif ! version="$(cmake_version_ok)"; then
    missing "CMake 3.31 or newer (found $version)" "brew upgrade cmake"
  fi
  command -v ninja >/dev/null || missing "Ninja" "brew install ninja"
  if [ -z "$LIBDISPATCH_SRC" ] && ! command -v git >/dev/null; then
    missing "git, to download libdispatch" "xcode-select --install"
  fi
  if [ ! -e "$CLANG" ] || { [ "$kind" = swift ] && [ ! -e "$SWIFTC" ]; }; then
    if [ "$SWIFT_TOOLCHAIN" = "$DEFAULT_SWIFT_TOOLCHAIN" ]; then
      missing "Swift 6.3.1 toolchain ($SWIFT_TOOLCHAIN)" \
        "swiftly install 6.3.1   (to get swiftly, see https://www.swift.org/install/macos/)"
    else
      missing "Swift toolchain ($SWIFT_TOOLCHAIN)" \
        "Install that toolchain, or unset SWIFT_TOOLCHAIN to use Swift 6.3.1."
    fi
  fi
  if [ ! -e "$SYSROOT" ] || [ ! -e "$BUILTINS" ] ||
     { [ "$kind" = swift ] && [ ! -e "$SWIFT_STATIC" ]; }; then
    if [ "$SWIFT_SDK_ID" = swift-6.3.1-RELEASE_wasm ]; then
      missing "Swift SDK for WASI ($SWIFT_SDK_ID), which must match the toolchain" \
        "$SWIFT sdk install $WASM_SDK_URL --checksum $WASM_SDK_CHECKSUM"
    else
      missing "Swift SDK for WASI ($WASM_SDK)" \
        "Install the Swift SDK $SWIFT_SDK_ID that matches SWIFT_TOOLCHAIN exactly."
    fi
  fi
  if [ "${RUN_WASMTIME:-0}" = 1 ] && ! command -v "$WASMTIME" >/dev/null; then
    missing "wasmtime, for --wasmtime" "brew install wasmtime"
  fi
  if [ "${NEED_PYTHON:-0}" = 1 ] && ! command -v python3 >/dev/null; then
    missing "Python 3, to serve the browser examples" "xcode-select --install"
  fi
  report_missing
  [ -n "$LIBDISPATCH_SRC" ] || fetch_libdispatch
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

# Download the default libdispatch tree, or update it to the latest commit of
# LIBDISPATCH_GIT_REF. Then use it as LIBDISPATCH_SRC. If the update fails,
# for example with no network, use the copy that is already there.
fetch_libdispatch() {
  local dir="$BUILD_ROOT/libdispatch-src"
  command -v git >/dev/null || fail "git is not on PATH. Install it with: xcode-select --install"
  mkdir -p "$BUILD_ROOT"
  if [ -d "$dir/.git" ] &&
     [ "$(git -C "$dir" remote get-url origin 2>/dev/null)" = "$LIBDISPATCH_GIT_URL" ]; then
    step "Update libdispatch ($LIBDISPATCH_GIT_REF)"
    if git -C "$dir" fetch --quiet --depth 1 origin "$LIBDISPATCH_GIT_REF"; then
      git -C "$dir" checkout --quiet --detach FETCH_HEAD
    else
      echo "    Could not update. Using the copy that is already there."
    fi
  else
    rm -rf "$dir"
    step "Download libdispatch ($LIBDISPATCH_GIT_REF)"
    git clone --quiet --depth 1 --branch "$LIBDISPATCH_GIT_REF" \
      "$LIBDISPATCH_GIT_URL" "$dir" ||
      fail "Could not download $LIBDISPATCH_GIT_URL. Check the network, or set LIBDISPATCH_SRC."
  fi
  echo "    $LIBDISPATCH_GIT_URL $LIBDISPATCH_GIT_REF at $(git -C "$dir" rev-parse --short HEAD)"
  LIBDISPATCH_SRC="$dir"
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
#   rest: --serve to also serve the folder on http://127.0.0.1:8080 (on this
#         machine only), --clean to delete the build folders first
build_browser_example() {
  local dir="$1"
  shift
  local serve=0 arg
  for arg in "$@"; do
    case "$arg" in
      --serve) serve=1; NEED_PYTHON=1 ;;
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
    step "Serve on http://127.0.0.1:8080"
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
        echo "Set LIBDISPATCH_SRC to use a local libdispatch tree with the WASI port."
        exit 0 ;;
      *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
  done
}
