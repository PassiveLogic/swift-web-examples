// Timers, cancellation, and blocking waits with Dispatch on WASI.
//
// Part 1 runs in main() and shows how a blocking wait behaves on one thread.
// Part 2 sets up timers, then calls dispatchMain() to run them.
import Dispatch

#if canImport(WASILibc)
import WASILibc
#endif

// MARK: Part 1: blocking waits

// A wait in main() runs other queued work until the wait can finish. Here a
// closure on a global queue signals the semaphore, and the wait runs it.
let semaphore = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    print("1. the global-queue closure ran inside the wait")
    semaphore.signal()
}
semaphore.wait()
print("1. the wait returned after the signal")

// A timed wait with nothing to run times out at its deadline.
let result = semaphore.wait(timeout: .now() + .milliseconds(50))
print("2. a timed wait with no signal returned .\(result == .timedOut ? "timedOut" : "success")")

// A wait never runs main-queue work, as on Darwin and Linux. The main-queue
// closure waits for dispatchMain().
var mainQueueRan = false
DispatchQueue.main.async { mainQueueRan = true }
DispatchQueue.global().async { semaphore.signal() }
semaphore.wait()
print("3. after the wait, the main-queue closure ran: \(mainQueueRan)")

// MARK: Part 2: timers

// A repeating timer source that fires 4 times, then cancels itself.
var ticks = 0
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20))
timer.setEventHandler {
    ticks += 1
    print("4. timer tick \(ticks)")
    if ticks == 4 { timer.cancel() }
}
timer.resume()

// A work item that is cancelled before its deadline never runs.
let cancelled = DispatchWorkItem { print("FAIL: the cancelled work item ran") }
DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50), execute: cancelled)
cancelled.cancel()

// A one-shot closure after 150 ms checks the results and ends the program.
let start = DispatchTime.now()
DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
    let elapsed = (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    print("5. asyncAfter ran after \(elapsed) ms, with \(ticks) timer ticks")
    print(ticks == 4 && mainQueueRan ? "done" : "FAIL: unexpected state")
    exit(0)
}

// dispatchMain() runs the main-queue closure from step 3, then sleeps until
// each timer is due.
dispatchMain()
