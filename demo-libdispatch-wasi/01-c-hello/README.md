# 01: Hello, Dispatch in C

The smallest libdispatch program for WASI. [main.c](./main.c) queues three blocks on a serial queue. When they are done, a block on the main queue prints a summary and calls `exit(0)`.

```
./run.sh             # build libdispatch, compile main.c, run it with WasmKit
./run.sh --wasmtime  # also run it with wasmtime
```

Expected output:

```
main() queued 3 blocks
block 1 ran on the serial queue
block 2 ran on the serial queue
block 3 ran on the serial queue
all blocks are done
```

Points to see in the code:

- `dispatch_async` never runs a block before it returns. So `main()` prints its line first.
- WASI has one thread. `dispatch_main()` runs the queued blocks on it. It never returns, so the last block ends the program with `exit(0)`.

See the [examples README](../README.md) for the prerequisites and the execution model.
