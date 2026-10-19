// The same tour as demo.c, written in Swift with `import Dispatch`.
//
// Each check prints one line that starts with "PASS [name]" or "FAIL [name]".
// The last line is a summary. The program exits with 0 only if every check
// passes.
//
// The rule from demo.c applies here too. WASI gives the program one thread.
// So `async` never runs a closure before it returns. Queued work runs later,
// at a pump point: a blocking wait at top level, or dispatchMain().
// Every wait in this file happens at top level, never inside a closure that
// Dispatch runs.

import Dispatch

#if canImport(WASILibc)
import WASILibc
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

var checksRun = 0
var checksFailed = 0

func report(_ ok: Bool, _ name: String, _ detail: String) {
    checksRun += 1
    if !ok {
        checksFailed += 1
    }
    print("\(ok ? "PASS" : "FAIL") [\(name)] \(detail)")
}

// Milliseconds on the monotonic clock.
func nowMs() -> Int64 {
    Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
}

// A small box, so closures can change a value that the checks read later.
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

// Line buffering keeps the output if the program traps part way.
setvbuf(stdout, nil, _IOLBF, 0)
print("libdispatch on WASI: basic checks (Swift)")

let global = DispatchQueue.global()

// 1. async to a global queue. The closure must not run before async returns.
do {
    let ran = Box(false)
    let done = DispatchSemaphore(value: 0)
    global.async {
        ran.value = true
        done.signal()
    }
    let ranTooEarly = ran.value
    let result = done.wait(timeout: .now() + .seconds(2))
    report(!ranTooEarly && ran.value && result == .success, "async",
           "global-queue closure ran later, not inside async")
}

// 2. A serial queue runs closures one at a time, in FIFO order.
do {
    let serial = DispatchQueue(label: "demo.serial")
    let group = DispatchGroup()
    let order = Box([Int]())
    for i in 0..<8 {
        serial.async(group: group) { order.value.append(i) }
    }
    let result = group.wait(timeout: .now() + .seconds(2))
    report(result == .success && order.value == Array(0..<8), "serial-fifo",
           "8 closures on a serial queue ran in order")
}

// 3. sync runs the closure before it returns, and can return a value.
//    When earlier async work is still queued, sync waits for it.
do {
    let serial = DispatchQueue(label: "demo.sync")
    let value = Box(0)
    let first: Int = serial.sync {
        value.value = 1
        return value.value
    }
    serial.async { value.value = 2 }
    let second = serial.sync { value.value }
    report(first == 1 && second == 2, "sync",
           "sync ran inline, then waited for earlier async work")
}

// 4. A group tracks several closures. notify runs after they all finish.
do {
    let group = DispatchGroup()
    let notified = DispatchSemaphore(value: 0)
    let finished = Box(0)
    let finishedAtNotify = Box(-1)
    for _ in 0..<4 {
        global.async(group: group) { finished.value += 1 }
    }
    group.notify(queue: global) {
        finishedAtNotify.value = finished.value
        notified.signal()
    }
    let waitResult = group.wait(timeout: .now() + .seconds(2))
    let notifyResult = notified.wait(timeout: .now() + .seconds(2))
    report(waitResult == .success && notifyResult == .success &&
           finished.value == 4 && finishedAtNotify.value == 4, "group",
           "group wait saw 4 closures finish, then notify ran")
}

// 5. Semaphores: a signal lets one wait go through at once.
//    A timed wait with no signal times out after its deadline.
do {
    let sema = DispatchSemaphore(value: 0)
    sema.signal()
    let first = sema.wait(timeout: .now())
    let start = nowMs()
    let second = sema.wait(timeout: .now() + .milliseconds(50))
    let waited = nowMs() - start
    report(first == .success && second == .timedOut && waited >= 50, "semaphore",
           "signal then wait succeeded, timed wait timed out after \(waited) ms")
}

// 6. asyncAfter runs a closure no earlier than its deadline.
do {
    let done = DispatchSemaphore(value: 0)
    let firedAt = Box<Int64>(0)
    let start = nowMs()
    global.asyncAfter(deadline: .now() + .milliseconds(100)) {
        firedAt.value = nowMs()
        done.signal()
    }
    let result = done.wait(timeout: .now() + .seconds(5))
    let delay = firedAt.value - start
    report(result == .success && delay >= 100, "after",
           "closure asked for 100 ms, ran after \(delay) ms")
}

// 7. A repeating timer source fires every 20 ms.
//    After 5 fires it cancels itself. The cancel handler then runs.
do {
    let queue = DispatchQueue(label: "demo.timer")
    let cancelled = DispatchSemaphore(value: 0)
    let timer = DispatchSource.makeTimerSource(queue: queue)
    let fires = Box(0)
    let start = nowMs()
    timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20))
    timer.setEventHandler {
        fires.value += 1
        if fires.value == 5 {
            timer.cancel()
        }
    }
    timer.setCancelHandler { cancelled.signal() }
    timer.resume()
    let result = cancelled.wait(timeout: .now() + .seconds(5))
    let elapsed = nowMs() - start
    report(result == .success && fires.value == 5 && elapsed >= 100, "timer",
           "timer fired \(fires.value) times in \(elapsed) ms, then cancelled itself")
}

// 8. concurrentPerform (dispatch_apply in C) runs a closure once per index.
do {
    let seen = Box([Int](repeating: 0, count: 10))
    DispatchQueue.concurrentPerform(iterations: 10) { i in
        seen.value[i] += 1
    }
    report(seen.value == [Int](repeating: 1, count: 10), "apply",
           "concurrentPerform ran each of 10 iterations once")
}

// 9. A user-data source with DATA_ADD adds up merged values.
//    All 3 merges happen before the next pump point, so the handler
//    runs one time and sees the total.
do {
    let queue = DispatchQueue(label: "demo.data-add")
    let handled = DispatchSemaphore(value: 0)
    let source = DispatchSource.makeUserDataAddSource(queue: queue)
    let total = Box<UInt>(0)
    let calls = Box(0)
    source.setEventHandler {
        total.value += source.data
        calls.value += 1
        handled.signal()
    }
    source.resume()
    source.add(data: 1)
    source.add(data: 2)
    source.add(data: 3)
    let result = handled.wait(timeout: .now() + .seconds(2))
    report(result == .success && total.value == 6 && calls.value == 1,
           "data-add-source",
           "merged 1+2+3, handler saw \(total.value) in \(calls.value) call(s)")
    source.cancel()
}

// 10. DispatchData: join two buffers and read the bytes back.
do {
    var joined = DispatchData.empty
    for part in ["Hello, ", "WASI!"] {
        Array(part.utf8).withUnsafeBytes { joined.append($0) }
    }
    let text = String(decoding: Array(joined), as: UTF8.self)
    report(text == "Hello, WASI!" && joined.count == 12, "data",
           "append + read gave \"\(text)\" (\(joined.count) bytes)")
}

// 11. dispatchMain() runs the main queue and sleeps until the next timer.
//     It never returns. The last main-queue closure prints the summary and
//     calls exit().
let mainStart = nowMs()
DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
    let waited = nowMs() - mainStart
    report(waited >= 50, "dispatch-main",
           "main-queue closure ran \(waited) ms later, inside dispatchMain()")
    if checksFailed == 0 {
        print("ALL \(checksRun) CHECKS PASSED")
    } else {
        print("\(checksRun - checksFailed) of \(checksRun) checks passed, \(checksFailed) FAILED")
    }
    exit(checksFailed == 0 ? 0 : 1)
}
dispatchMain()
