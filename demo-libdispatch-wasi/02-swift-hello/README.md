# 02: Hello, Dispatch in Swift

The same program as [01-c-hello](../01-c-hello/README.md), in Swift with `import Dispatch`. [main.swift](./main.swift) queues three closures on a serial queue. When they are done, a closure on the main queue prints a summary and calls `exit(0)`.

```
./run.sh             # build libdispatch with the Swift overlay, compile, run with WasmKit
./run.sh --wasmtime  # also run it with wasmtime
```

Expected output:

```
main queued 3 closures
closure 1 ran on the serial queue
closure 2 ran on the serial queue
closure 3 ran on the serial queue
all closures are done
```

The Swift SDK for WASI has no Dispatch module. So the run script builds the Swift overlay from the libdispatch source, and it compiles with `-I` and `-L` flags for it. The Dispatch module names its own libraries for the linker.
