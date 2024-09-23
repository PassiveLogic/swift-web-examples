# SwiftWasm Interoperable Hello World POC

## Description

- Demonstrates passing string types from Swift to JS and vice versa.
- The primary files here are main.swift and main.mjs. The swift package is used to employ swift carton to build the wasm.

## Getting started

Clone this repo and run the following command:

```
./demo.command
```

Expected output:

```
...
Hello From Swift!
[WASI stdout] Hello From JS!
```

## How it works

### Sending string from Swift to JS

Step 1 - call swift function from JS to populate string

[main.mjs](./main.mjs#L52)
```
// Call Swift function that populates the string to JS memory
const getStringFromSwiftFn = instance.exports.getStringFromSwift;
getStringFromSwiftFn() // ℹ️ String passed from Swift to JS here

```

Step 2 - Swift function populates string in js-readable memory

[Sources/main.swift](./Sources/main.swift#L19)
```
/// Populates string to memory readable by JS.
@_expose(wasm, "getStringFromSwift")
@_cdecl("getStringFromSwift")
func getStringFromSwift() {
    JSObject.global.messageFromSwift = "Hello From Swift!".jsValue
}

```

Step 3 - JS parses and reads the memory value populated from Swift

[main.mjs](./main.mjs#L58)
```
// Get the message from Swift to JS
const messageFromSwift = globalThis.messageFromSwift
console.log(messageFromSwift)
```

### Sending string from JS to Swift

Step 4 - Register receiving Swift closure from JS

[main.mjs](./main.mjs#L64)
```
const installSwiftMessengerClosureFn = instance.exports.installSwiftMessengerClosure;
installSwiftMessengerClosureFn() // Run this func to populate message in globalThis

```

Step 5 - Swift installation function sets up closure to receive the string and print out to console (as an example)

[Sources/main.swift](./Sources/main.swift#L33)
```
/// Called by JS to install a closure that receives the string.
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

```

Step 6 - Send the string from JS to Swift

[main.mjs](./main.mjs#L70)
```
// Send string to Swift
const swiftMessenger = globalThis.swiftMessenger
swiftMessenger("Hello From JS!") // ℹ️ String passed from JS to Swift here
```

