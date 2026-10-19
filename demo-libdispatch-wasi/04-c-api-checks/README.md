# 04: C API checks

[demo.c](./demo.c) checks 12 parts of the libdispatch C API. Each check prints a `PASS` or `FAIL` line, and the program ends with a summary.

```
./run.sh             # build, compile, and run with WasmKit
./run.sh --wasmtime  # also run it with wasmtime
```

| Check | What it shows |
|---|---|
| `async` | `dispatch_async` to a global queue. The block runs later, not inside `dispatch_async`. |
| `serial-fifo` | A serial queue runs its blocks in FIFO order. |
| `sync` | `dispatch_sync` runs inline, and waits for earlier async work. |
| `group` | `dispatch_group_async`, `dispatch_group_wait`, and `dispatch_group_notify`. |
| `semaphore` | `dispatch_semaphore_signal` and `dispatch_semaphore_wait`, and a timed wait that times out. |
| `after` | `dispatch_after` runs a block no earlier than its deadline. |
| `timer` | A repeating timer source that cancels itself after 5 fires. |
| `apply` | `dispatch_apply` runs each index one time. |
| `once` | `dispatch_once` runs its block one time. |
| `data-add-source` | A `DISPATCH_SOURCE_TYPE_DATA_ADD` source adds up merged values. |
| `data` | `dispatch_data_create_concat` and `dispatch_data_create_map`. |
| `dispatch-main` | `dispatch_main()` sleeps to a timer, runs a main-queue block, and the block calls `exit(0)`. |

The run script checks for the line `ALL 12 CHECKS PASSED`, an exit status of 0, and no `FAIL` line.
