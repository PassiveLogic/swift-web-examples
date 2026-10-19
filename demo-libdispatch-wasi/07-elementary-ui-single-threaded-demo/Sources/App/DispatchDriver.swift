import CDispatchHost
import Dispatch
import ElementaryUI
import JavaScriptKit
import Reactivity

/// The queues that the page can send blocks to.
enum Lane: String, CaseIterable {
    case main
    case userInitiated = "user-initiated"
    case standard = "default"
    case utility

    var queue: DispatchQueue {
        switch self {
        case .main: return .main
        case .userInitiated: return .global(qos: .userInitiated)
        case .standard: return .global(qos: .default)
        case .utility: return .global(qos: .utility)
        }
    }
}

/// A block that the page queued and that has not run yet.
struct PendingBlock {
    let id: Int
    let label: String
    let lane: Lane
}

/// What one drain step, or one top-level wait, ran.
struct StepRecord {
    enum Kind: String {
        case main, root, internalStep = "internal", idle, wait
    }
    let number: Int
    let kind: Kind
    let title: String
    let ran: [String]
}

/// Drives Dispatch one drain step at a time through the host event loop SPI,
/// and keeps a record of each step.
///
/// Dispatch does not list its pending blocks, so the model keeps its own list
/// of the blocks that the page queued. Each block removes itself from that
/// list when it runs.
@Reactive
final class DispatchDriver {
    var pending: [Lane: [PendingBlock]] = [:]
    var timers: [String] = []
    var steps: [StepRecord] = []
    /// True after Dispatch asks for a host turn, until a step consumes it.
    var turnRequested = false
    var nextTimer = "none"
    var autoRun = false

    private var nextID = 1
    private var ranInThisStep: [String] = []
    private var autoTimer: JSValue = .undefined
    private var autoClosure: JSClosure?

    // MARK: Queue work

    /// Queue a block. A block with reposts > 0 queues itself again after it
    /// runs, so it shows how Dispatch shares the thread.
    func enqueue(_ lane: Lane, _ label: String, reposts: Int = 0,
                 action: (() -> Void)? = nil) {
        let block = PendingBlock(id: takeID(), label: label, lane: lane)
        pending[lane, default: []].append(block)
        lane.queue.async {
            self.didRun(block)
            action?()
            if reposts > 0 {
                self.enqueue(lane, label, reposts: reposts - 1, action: action)
            }
        }
    }

    /// Queue a block that runs after one second.
    func enqueueAfterOneSecond() {
        let label = "after 1 s #\(nextID)"
        timers.append(label)
        Lane.standard.queue.asyncAfter(deadline: .now() + .seconds(1)) {
            self.timers.removeAll { $0 == label }
            self.ranInThisStep.append("\(label) (default)")
        }
        refreshNextTimer()
    }

    /// Queue a block with the C API (dispatch_async_f) on the default queue.
    func enqueueC() {
        let block = PendingBlock(id: takeID(), label: "C block", lane: .standard)
        pending[.standard, default: []].append(block)
        cBlocks.append(block)
        c_async_on_default_queue({ _ in driver.didRunC() }, nil)
    }

    private var cBlocks: [PendingBlock] = []

    private func didRunC() {
        if !cBlocks.isEmpty { didRun(cBlocks.removeFirst()) }
    }

    private func didRun(_ block: PendingBlock) {
        pending[block.lane]?.removeAll { $0.id == block.id }
        ranInThisStep.append("\(block.label) (\(block.lane.rawValue))")
    }

    private func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    // MARK: Run work

    /// Run one drain step through the host event loop SPI.
    func step() {
        ranInThisStep = []
        let consumes = turnRequested
        let timerDue = _dispatch_wasi_event_loop_next_timer_delay() == 0
        // Clear the flag first. If work remains, Dispatch asks for the next
        // turn during perform(), and the scheduler sets the flag again.
        turnRequested = false
        _ = _dispatch_wasi_event_loop_perform(1, consumes)
        record(kind: classify(ran: ranInThisStep, hadWork: consumes || timerDue))
        refreshNextTimer()
    }

    /// Wait for a semaphore in a click handler. The utility block signals it.
    /// A top-level wait runs root-queue blocks and timers, but never
    /// main-queue blocks.
    func topLevelWait() {
        let semaphore = DispatchSemaphore(value: 0)
        enqueue(.utility, "signal") { semaphore.signal() }
        ranInThisStep = []
        semaphore.wait()
        record(kind: .wait)
        refreshNextTimer()
    }

    func toggleAutoRun() {
        autoRun.toggle()
        if autoRun {
            let closure = JSClosure { _ in
                driver.step()
                return .undefined
            }
            autoClosure = closure
            autoTimer = JSObject.global.setInterval!(closure, 300)
        } else {
            _ = JSObject.global.clearInterval!(autoTimer)
            autoClosure = nil
        }
    }

    func clearSteps() {
        steps = []
    }

    // MARK: Records

    private func classify(ran: [String], hadWork: Bool) -> StepRecord.Kind {
        guard let first = ran.first else { return hadWork ? .internalStep : .idle }
        return first.hasSuffix("(main)") ? .main : .root
    }

    private func record(kind: StepRecord.Kind) {
        let title: String
        switch kind {
        case .main: title = "main queue"
        case .root: title = "root queue"
        case .internalStep: title = "timer or manager"
        case .idle: title = "no work"
        case .wait: title = "top-level wait"
        }
        steps.append(StepRecord(number: steps.count + 1, kind: kind,
                                title: title, ran: ranInThisStep))
        if steps.count > 60 { steps.removeFirst(steps.count - 60) }
    }

    func refreshNextTimer() {
        let delay = _dispatch_wasi_event_loop_next_timer_delay()
        switch delay {
        case ..<0: nextTimer = "none"
        case 0: nextTimer = "due now"
        default: nextTimer = "in \(delay / 1_000_000) ms"
        }
    }
}

/// The one model. A global, so the C scheduler callback can reach it.
let driver = DispatchDriver()

/// Connect Dispatch to the page. The page runs steps itself, so the
/// scheduler only notes that Dispatch asked for a turn.
func installScheduler() {
    _dispatch_wasi_event_loop_set_scheduler({ _ in
        driver.turnRequested = true
    }, nil)
    driver.refreshNextTimer()
}
