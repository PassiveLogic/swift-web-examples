import JavaScriptKit // See https://github.com/swiftwasm/JavaScriptKit

/// NOTE: This file documents a mechanism for passing Strings between
/// Swift and JavaScript. There is an example for exporting
/// Swift functions to JavaScript, documented here
///
/// http://book.swiftwasm.org/examples/exporting-function.html#swift-60-or-later
/// 
/// The example doesn't mention that there are limitations with
/// Wasm and exporting functions that restrict the parameter types
/// to integers only.

/// Sends a `String`` from Swift to JavaScript by populating the string 
/// to memory readable by JavaScript, using JavaScriptKit.
@_expose(wasm, "getStringFromSwift")
@_cdecl("getStringFromSwift")
func getStringFromSwift() {
    // 2
    JSObject.global.messageFromSwift = "Hello From Swift!".jsValue
}

/// Aids sending a `String` from JavaScript to Swift by installing
/// closure that JavaScript can call to pass the `String`.
///
/// This function must first be executed to install the closure.
///
/// Once the closure is installed, JavaScript calls the closure
/// to send the string from JavaScript to Swift.
@_expose(wasm, "installSwiftMessengerClosure")
@_cdecl("installSwiftMessengerClosure")
func installSwiftMessengerClosure() {
    // 5
    let closure = JSClosure { jsValues in
        if let firstMessage = jsValues.compactMap({ $0.jsString }).first {
            print(firstMessage)
        }
        
        return .undefined
    }
    JSObject.global.swiftMessenger = closure.jsValue
}
