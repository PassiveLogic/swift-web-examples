import CDispatchHost
import Dispatch
import JavaScriptKit

// Connect Dispatch to the browser event loop first.
HostLoop.install()

let document = JSObject.global.document
let log = document.getElementById("log")

/// Add a line to the log on the page. Call it from the main queue or from
/// browser code, never from a global-queue block. On WASI, a global-queue
/// block runs as a worker, so the precondition stops the program there.
func show(_ text: String) {
    dispatchPrecondition(condition: .onQueue(.main))
    let item = document.createElement("li")
    item.textContent = .string(text)
    _ = log.appendChild(item)
}

// A repeating timer on the main queue updates the clock on the page.
var seconds = 0
let clock = DispatchSource.makeTimerSource(queue: .main)
clock.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
clock.setEventHandler {
    seconds += 1
    document.getElementById("clock").textContent = .string("\(seconds) s")
}
clock.resume()

// Swift work: a serial queue runs three closures in order, and a group
// reports on the main queue when they are done. Only the serial queue
// writes the results.
let workQueue = DispatchQueue(label: "swift-work")
var results: [Int] = []

func runSwiftWork() {
    let group = DispatchGroup()
    workQueue.async(group: group) { results.removeAll() }
    for i in 1...3 {
        workQueue.async(group: group) { results.append(i * i) }
    }
    show("Swift: queued 3 closures on a serial queue")
    group.notify(queue: .main) {
        show("Swift: the group finished with results \(results)")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
        show("Swift: asyncAfter ran 500 ms later")
    }
}

// C work: the C target counts primes on a global queue with
// dispatch_async_f, then reports on the main queue.
func runCWork() {
    show("C: counting the primes below 200000 on a global queue")
    c_count_primes_async(200_000, { primes, _ in
        show("C: found \(primes) primes, reported on the main queue")
    }, nil)
}

let swiftButton = document.getElementById("swift-work")
swiftButton.onclick = .object(JSClosure { _ in
    runSwiftWork()
    return .undefined
})
let cButton = document.getElementById("c-work")
cButton.onclick = .object(JSClosure { _ in
    runCWork()
    return .undefined
})

// Run both once at startup. The work runs in later browser tasks.
DispatchQueue.main.async { show("Dispatch is running in the browser") }
runSwiftWork()
runCWork()
