# 06: Dispatch in the browser

A web page in Swift that uses Dispatch. A page cannot call `dispatchMain()`, because that would block the page. Instead, the browser event loop drives Dispatch through the host event loop SPI of libdispatch.

```
./build.sh           # build libdispatch with the Swift overlay, then this package
./build.sh --serve   # also serve the page on http://localhost:8080 (this machine only)
```

Open http://localhost:8080 in a browser. The page shows a clock that a `DispatchSourceTimer` updates, and a log of the work that ran. The buttons queue more work.

## The code

- [HostLoop.swift](./Sources/App/HostLoop.swift) connects Dispatch to the browser. Read this file first.
  1. Dispatch calls the scheduler when it records work. The scheduler queues a browser task with `setTimeout(0)` and returns at once.
  2. The browser task calls `_dispatch_wasi_event_loop_perform()`. Dispatch runs up to 64 drain steps.
  3. After each perform call, the host asks for the next timer delay with `_dispatch_wasi_event_loop_next_timer_delay()`. It keeps one browser timeout for it.
- [main.swift](./Sources/App/main.swift) is the page. It uses `DispatchQueue`, `DispatchGroup`, `asyncAfter`, and a timer source.
- The browser timeout uses one reusable callback. A cancelled timeout never runs its callback, so a one-shot callback would never be freed.
- [CDispatchHost](./Sources/CDispatchHost) is a C target. Its header declares the three SPI functions, because libdispatch does not install a header for private SPI. [primes.c](./Sources/CDispatchHost/primes.c) queues work with the C API: it counts primes on a global queue with `dispatch_async_f`, then reports on the main queue.

## How it builds

The package uses the `PackageToJS` plugin of [JavaScriptKit](https://github.com/swiftwasm/JavaScriptKit). The plugin builds a reactor module, so the module stays alive after `main` returns, and the browser can call into it. [Package.swift](./Package.swift) adds `-I` and `-L` flags for the Dispatch build in `LIBDISPATCH_SWIFT_LIBS`. [build.sh](./build.sh) sets that variable.

The debug build of `App.wasm` is about 10 MB, because it holds the full Swift runtime.
