import CDispatchHost
import JavaScriptKit

/// Drives Dispatch from the browser event loop.
///
/// A browser page cannot call dispatchMain(), because that would block the
/// page forever. Instead, Dispatch asks for a host turn when it records work,
/// and the browser calls back into Dispatch on its own turns:
///
/// 1. Dispatch calls the scheduler. The scheduler queues a browser task with
///    setTimeout(0) and returns at once.
/// 2. The browser task calls perform(). Dispatch runs a few drain steps.
/// 3. After each perform(), the host asks for the next timer delay and sets
///    one browser timeout for it.
enum HostLoop {
    /// The most drain steps in one browser task. A small number keeps the
    /// page responsive.
    static let stepsPerTurn: UInt = 64

    private static var timeoutID: JSValue = .undefined

    static func install() {
        // The scheduler is a C function pointer, so it cannot capture state.
        _dispatch_wasi_event_loop_set_scheduler({ _ in
            HostLoop.queueBrowserTask { HostLoop.turn(consumesScheduledTurn: true) }
        }, nil)
        // Dispatch hands over work from before the registration, including
        // an armed timer, so check the timer now.
        rearmTimer()
    }

    /// One scheduled host turn, or one timer wake.
    private static func turn(consumesScheduledTurn: Bool) {
        // A true result means Dispatch already asked for the next turn.
        _ = _dispatch_wasi_event_loop_perform(stepsPerTurn, consumesScheduledTurn)
        rearmTimer()
    }

    /// Replace the one browser timeout with one for the next Dispatch timer.
    private static func rearmTimer() {
        _ = JSObject.global.clearTimeout!(timeoutID)
        timeoutID = .undefined
        let delay = _dispatch_wasi_event_loop_next_timer_delay()
        guard delay >= 0 else { return }  // -1: no timer is armed
        let milliseconds = Double(delay) / 1_000_000
        timeoutID = JSObject.global.setTimeout!(JSOneshotClosure { _ in
            // A timer wake does not consume the scheduled turn.
            HostLoop.turn(consumesScheduledTurn: false)
            return .undefined
        }, milliseconds)
    }

    private static func queueBrowserTask(_ body: @escaping () -> Void) {
        _ = JSObject.global.setTimeout!(JSOneshotClosure { _ in
            body()
            return .undefined
        }, 0)
    }
}
