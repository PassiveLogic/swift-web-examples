# libdispatch on WASI Examples

These examples use libdispatch (Grand Central Dispatch) on WebAssembly, for the single-threaded `wasm32-unknown-wasip1` target. Each example is in its own folder, with its own README. The first examples are short and easy to read. The later examples show more of the runtime.

| Folder | Language | Runs in | What it shows |
|---|---|---|---|
| [01-c-hello](./01-c-hello/README.md) | C | WasmKit, wasmtime | The smallest program: a serial queue, a group, and `dispatch_main()` |
| [02-swift-hello](./02-swift-hello/README.md) | Swift | WasmKit, wasmtime | The same program with `import Dispatch` |
| [03-swift-timers-and-waits](./03-swift-timers-and-waits/README.md) | Swift | WasmKit, wasmtime | Timers, a cancelled work item, and how blocking waits behave on one thread |
| [04-c-api-checks](./04-c-api-checks/README.md) | C | WasmKit, wasmtime | 12 checks of the C API: queues, groups, semaphores, timers, sources, and data |
| [05-swift-api-checks](./05-swift-api-checks/README.md) | Swift | WasmKit, wasmtime | 11 checks of the Swift API |
| [06-browser-host-loop](./06-browser-host-loop/README.md) | Swift and C | A browser | The browser event loop drives Dispatch through the host event loop SPI |
| [07-elementary-ui-single-threaded-demo](./07-elementary-ui-single-threaded-demo/README.md) | Swift and C | A browser | The Single-threaded Demo, an [ElementaryUI](https://github.com/elementary-swift/elementary-ui) app. It runs one real Dispatch drain step at a time and shows what each step ran |

## Prerequisites

- macOS with the Xcode command line tools.
- A Swift 6.3.1 release toolchain in `~/Library/Developer/Toolchains`.
- The matching Swift SDK for WASI (`swift-6.3.1-RELEASE_wasm`). Install it with `swift sdk install`.
- CMake 3.31 or newer. This is the first CMake that knows `CMAKE_SYSTEM_NAME=WASI`.
- Ninja.
- Git, and network access on the first run. The scripts download a [libdispatch](https://github.com/swiftlang/swift-corelibs-libdispatch) tree with the WASI port into `.build/libdispatch-src`, and update it on each run. Upstream libdispatch does not have the WASI port yet, so the default is the branch that holds the full port. See `LIBDISPATCH_GIT_URL` and `LIBDISPATCH_GIT_REF` below. To use your own tree, set `LIBDISPATCH_SRC`. It must have the cooperative WASI backend (`src/event/event_wasi.c`), and the Swift examples also need its Swift overlay support for WASI.
- For examples 01 to 05: WasmKit 0.3.0 or newer. See [WasmKit versions](#wasmkit-versions). wasmtime is optional.
- For examples 06 and 07: Python 3 for a local web server, and a browser. The first build downloads Swift packages from GitHub, and the page loads a WASI shim from a CDN.

## Getting started

Walk through the examples one at a time:

```
./run-all.sh
```

First the script checks the tools, downloads or updates libdispatch, and builds it. Then it shows each example and waits for you. Press Enter to run the example, `s` to skip it, or `q` to quit. The script builds a browser example and serves it on http://127.0.0.1:8080 until you press Enter.

Run every example without pausing, for example as a smoke test:

```
./run-all.sh --no-pause --wasmtime
```

The script prints a summary. If an example fails, it exits with a non-zero status. Without a terminal, the script does not pause.

Or run one example from its folder, for example `./01-c-hello/run.sh`. Options:

- `run-all.sh` and the command line examples take `--wasmtime` to also run with wasmtime.
- The browser examples take `--serve` to start a web server on http://127.0.0.1:8080. It accepts connections from this machine only.
- Every script takes `--clean` to delete the shared build folder first. In `run-all.sh` and the browser examples, `--clean` also deletes the package build folders of the browser examples.

These environment variables have defaults. Set them only to use other tools or another libdispatch tree.

| Variable | Default |
|---|---|
| `LIBDISPATCH_SRC` | the copy that the scripts download into `.build/libdispatch-src` |
| `LIBDISPATCH_GIT_URL` | `https://github.com/PassiveLogic/swift-corelibs-libdispatch.git` |
| `LIBDISPATCH_GIT_REF` | `feat/scottm/libDispatchWasmV2`, the branch with the full WASI port |
| `SWIFT_TOOLCHAIN` | `~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain` |
| `SWIFT_SDK_ID` | `swift-6.3.1-RELEASE_wasm` |
| `WASM_SDK` | the `wasm32-unknown-wasip1` folder of that Swift SDK |
| `WASMKIT` | the first WasmKit 0.3.0 or newer that the scripts find |
| `WASMTIME` | `wasmtime` on `PATH` |

`SWIFT_SDK_ID` and `WASM_SDK` must name the same Swift SDK. libdispatch builds against `WASM_SDK`, and the browser examples build with `SWIFT_SDK_ID`. If you set one, set the other to match.

## How the examples build

All examples share [common.sh](./common.sh) and one build folder, `.build`. Git ignores it.

1. Each example builds libdispatch and installs it into a stage folder. The source is `LIBDISPATCH_SRC`, or the downloaded copy in `.build/libdispatch-src`. `--clean` deletes that copy too, so the next run downloads it again. There are two kinds of build:
   - `.build/stage-c` holds the C library only. The C examples use it.
   - `.build/stage-swift` holds the C library and the Swift overlay. The Swift and browser examples use it.

   The first example that needs a kind of build compiles it. Later examples only compile what changed.
2. Each command line example compiles its source to a `.wasm` file in `.build`, then runs it.
3. Each browser example builds its Swift package with the `PackageToJS` plugin of [JavaScriptKit](https://github.com/swiftwasm/JavaScriptKit). Its `Package.swift` gets the stage folder from the `LIBDISPATCH_SWIFT_LIBS` variable, because the Swift SDK for WASI has no Dispatch module.

The C examples link `libdispatch.a`, `libBlocksRuntime.a`, three wasi-libc emulation libraries (signals, mmap, and getpid), and the wasm32 compiler-rt builtins from the Swift SDK. The Swift examples need only `-I` and `-L` flags. The Dispatch module names its own libraries for the linker.

## The execution model

WASI gives the program one thread. So libdispatch cannot run work on other threads. It runs all work on the one thread, at known points.

- `dispatch_async` never runs the block before it returns. The block waits in its queue.
- Queued work runs at a pump point. These are the pump points:
  - `dispatch_main()`. A command module calls it, as examples 01 to 05 do.
  - A host turn. A host event loop calls the private SPI `_dispatch_wasi_event_loop_perform()`, as examples 06 and 07 do.
  - A blocking Dispatch wait at top level, for example `dispatch_semaphore_wait` in `main()`. The wait runs other queued work until it can finish. It never runs main-queue work, as on Darwin and Linux.
- A blocking wait inside a block that Dispatch runs cannot run other work. An indefinite wait there stops the program with a message such as `Deadlock: semaphore wait from a work item`.
- `dispatch_main()` runs the queued work. When only timers are left, it sleeps until the next timer is due. It never returns. If nothing is left that can make more work, it stops the program with a message that starts with `dispatch_main() with no work`. So a command module ends with `exit(0)` from its last block.

## WasmKit versions

libdispatch sleeps until its next timer with `nanosleep`. In wasi-libc, `nanosleep` calls the WASI function `poll_oneoff`. WasmKit 0.3.0 is the first release that has `poll_oneoff`.

The Swift 6.3 and 6.3.1 toolchains ship WasmKit 0.1.6. With WasmKit 0.1.6, the examples still pass, but:

- Each sleep returns at once with an error, so libdispatch keeps checking the clock until the timer is due. This is a busy loop.
- WasmKit prints `"poll_oneoff" not implemented yet` to stdout for each sleep, many thousands of times. The scripts hide these lines.

If you do not set `WASMKIT`, the scripts look for WasmKit 0.3.0 or newer. They try `wasmkit` on `PATH` first, then the `wasmkit` in each installed Swift toolchain. A Swift development snapshot toolchain has a new enough WasmKit. If the scripts find only an older WasmKit, they use it and print a warning.
