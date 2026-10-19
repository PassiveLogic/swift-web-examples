import ElementaryUI

@View
struct AppView {
    var body: some View {
        div(.class("page")) {
            header {
                h1 { "Single-threaded Demo" }
                p(.class("lede")) {
                    "libdispatch for WASI runs every queue on one thread. "
                    "Queue some blocks, then run Dispatch one drain step at a time and see "
                    "which queue each step serves."
                }
            }
            RunControls(driver: driver)
            QueueControls(driver: driver)
            PendingBlocks(driver: driver)
            StepHistory(driver: driver)
        }
    }
}

@View
struct RunControls {
    var driver: DispatchDriver

    var body: some View {
        section(.class("panel")) {
            h2 { "Run" }
            div(.class("controls")) {
                button(.class("primary")) { "Step" }
                    .onClick { _ in driver.step() }
                button { driver.autoRun ? "Stop" : "Auto step" }
                    .onClick { _ in driver.toggleAutoRun() }
                button { "Top-level wait" }
                    .onClick { _ in driver.topLevelWait() }
                button { "Clear history" }
                    .onClick { _ in driver.clearSteps() }
            }
            p(.class("status")) {
                "Turn requested: "
                b { driver.turnRequested ? "yes" : "no" }
                span(.class("separator")) { " | " }
                "Next timer: "
                b { driver.nextTimer }
            }
        }
    }
}

@View
struct QueueControls {
    var driver: DispatchDriver

    var body: some View {
        section(.class("panel")) {
            h2 { "Queue work" }
            div(.class("controls")) {
                button { "Main" }
                    .onClick { _ in driver.enqueue(.main, "main block") }
                button { "Main, repeats 5 times" }
                    .onClick { _ in driver.enqueue(.main, "repeating main", reposts: 4) }
                button { "User-initiated" }
                    .onClick { _ in driver.enqueue(.userInitiated, "block") }
                button { "Default" }
                    .onClick { _ in driver.enqueue(.standard, "block") }
                button { "Default, from C" }
                    .onClick { _ in driver.enqueueC() }
                button { "Utility, repeats 5 times" }
                    .onClick { _ in driver.enqueue(.utility, "repeating", reposts: 4) }
                button { "Timer, 1 s" }
                    .onClick { _ in driver.enqueueAfterOneSecond() }
            }
        }
    }
}

@View
struct PendingBlocks {
    var driver: DispatchDriver

    var body: some View {
        section {
            h2 { "Pending blocks" }
            div(.class("board")) {
                for lane in Lane.allCases {
                    div(.class("column")) {
                        h3 { lane.rawValue }
                        ForEach(driver.pending[lane] ?? [], key: { String($0.id) }) { block in
                            div(.class("chip \(lane == .main ? "main" : "root")")) { block.label }
                        }
                    }
                }
                div(.class("column")) {
                    h3 { "timers" }
                    ForEach(driver.timers, key: { $0 }) { label in
                        div(.class("chip timer")) { label }
                    }
                }
            }
        }
    }
}

@View
struct StepHistory {
    var driver: DispatchDriver

    var body: some View {
        section {
            h2 { "Drain steps" }
            p(.class("hint")) { "Each box is one drain step. The newest step is on the right." }
            div(.class("lane")) {
                if driver.steps.isEmpty {
                    p(.class("empty")) { "No steps yet. Queue some blocks, then press Step." }
                }
                ForEach(driver.steps, key: { String($0.number) }) { record in
                    div(.class("tick \(record.kind.rawValue)")) {
                        span(.class("number")) { "#\(record.number)" }
                        b { record.title }
                        for line in record.ran {
                            span { line }
                        }
                    }
                }
            }
        }
    }
}
