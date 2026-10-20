// The smallest Dispatch program for WASI, in Swift.
//
// It queues three closures on a serial queue. When they are done, a closure
// on the main queue prints a summary and ends the program.
import Dispatch

#if canImport(WASILibc)
import WASILibc
#endif

let queue = DispatchQueue(label: "hello")
let group = DispatchGroup()

for i in 1...3 {
    queue.async(group: group) {
        print("closure \(i) ran on the serial queue")
    }
}

// async never runs a closure before it returns. So this line prints first.
print("main queued 3 closures")

group.notify(queue: .main) {
    print("all closures are done")
    exit(0)
}

// WASI has one thread. dispatchMain() runs the queued work on it.
// It never returns. The notify closure above ends the program.
dispatchMain()
