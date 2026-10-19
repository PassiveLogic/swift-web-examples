# 05: Swift API checks

[demo.swift](./demo.swift) does the checks of [04-c-api-checks](../04-c-api-checks/README.md) with the Swift API: `DispatchQueue`, `DispatchGroup`, `DispatchSemaphore`, `asyncAfter`, `DispatchSourceTimer`, `concurrentPerform`, a data-add source, `DispatchData`, and `dispatchMain()`. Swift has no `dispatch_once`, so there are 11 checks.

```
./run.sh             # build libdispatch with the Swift overlay, compile, run with WasmKit
./run.sh --wasmtime  # also run it with wasmtime
```

The run script checks for the line `ALL 11 CHECKS PASSED`, an exit status of 0, and no `FAIL` line.

The Swift example is about 3.5 MB, because it holds the static Swift runtime. The C example of 04 is about 160 KB.
