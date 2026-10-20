# 03: Timers and waits in Swift

[main.swift](./main.swift) shows how timers and blocking waits behave when Dispatch has one thread.

```
./run.sh             # build, compile, and run with WasmKit
./run.sh --wasmtime  # also run it with wasmtime
```

Expected output (the time changes a little from run to run):

```
1. the global-queue closure ran inside the wait
1. the wait returned after the signal
2. a timed wait with no signal returned .timedOut
3. after the wait, the main-queue closure ran: false
4. timer tick 1
4. timer tick 2
4. timer tick 3
4. timer tick 4
5. asyncAfter ran after 150 ms, with 4 timer ticks
done
```

What each part shows:

1. A wait in `main()` runs other queued work until the wait can finish. The closure that signals the semaphore runs inside the wait.
2. A timed wait with nothing to run times out at its deadline.
3. A wait never runs main-queue work, as on Darwin and Linux. The main-queue closure runs later, in `dispatchMain()`.
4. A repeating `DispatchSourceTimer` fires 4 times, then cancels itself.
5. A cancelled `DispatchWorkItem` never runs. `asyncAfter` runs after its deadline, then ends the program.

Do not wait inside a closure that Dispatch runs. Such a wait cannot run other work, so an indefinite wait there stops the program with a named message.
