# 07: Single-threaded Demo (ElementaryUI)

A full-stack Swift web app. It is built with [ElementaryUI](https://github.com/elementary-swift/elementary-ui) and runs the real libdispatch for WASI. The page runs one Dispatch drain step at a time, so you can see how the one thread shares its time between queues.

```
./build.sh           # build libdispatch with the Swift overlay, then this package
./build.sh --serve   # also serve the page on http://localhost:8080
```

Open http://localhost:8080 in a browser.

## How to use it

1. Queue blocks with the **Queue work** buttons: main-queue blocks, global-queue blocks at three QoS levels, blocks that repeat by queueing themselves again, a block that the C API queues, and an `asyncAfter` timer.
2. Press **Step**. The page calls `_dispatch_wasi_event_loop_perform()` for one drain step, and adds a box to **Drain steps**. The box shows what the step ran.
3. Press **Auto step** to step every 300 ms.
4. Press **Top-level wait** to wait for a semaphore in the click handler. A utility block signals it.

Things to try:

- Queue a repeating main block and a repeating utility block. The main queue and the root queues take turns, so neither one keeps the thread.
- Queue blocks at all three QoS levels. The root queues run from the highest QoS down.
- Queue a main block and a default block, then press **Top-level wait**. The wait runs the default block and the signal, but the main block stays pending. A wait never runs main-queue work.
- Queue an `asyncAfter` timer. The next step is a manager step that arms the timer. When the timer is due, a timer step fires it, and a later step runs its block.

## The code

- [DispatchDriver.swift](./Sources/App/DispatchDriver.swift) is the model. It queues the blocks, runs the steps, and keeps a record of them. Dispatch has no API to list pending blocks, so the model keeps its own list. Each block removes itself from the list when it runs.
- [Views.swift](./Sources/App/Views.swift) is the ElementaryUI user interface.
- [CDispatchHost](./Sources/CDispatchHost) is a C target. It declares the host event loop SPI, and it queues a block with `dispatch_async_f`.

The scheduler callback does not queue a browser task here, unlike [06-browser-host-loop](../06-browser-host-loop/README.md). It only notes that Dispatch asked for a turn. The page runs a step only when you press **Step**, so you can watch each one.

## Versions

- ElementaryUI 0.7.0. It is the last release for Swift 6.3. Version 0.8 needs Swift 6.4.
- swift-collections 1.6. ElementaryUI 0.7.0 does not build with 1.7.
- The full Swift SDK, not the Embedded Swift SDK, because the Dispatch overlay needs full Swift.

The debug build of `App.wasm` is about 22 MB.
