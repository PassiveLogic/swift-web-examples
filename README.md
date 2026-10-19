# Swift on the Web

This repository shows a few examples of how to use Swift on the Web.

## String-based Swift-JS API's

Demonstrates passing data as a String between Swift and JavaScript.

Builds off of the [example from the SwiftWasm book](http://book.swiftwasm.org/examples/exporting-function.html) that shows passing Integer types.

See [here](./demo-swift-string-parameters/README.md) for details.

## Tokamak SwiftUI on the Web

Demonstrates a basic web app uses SwiftUI via Tokamak for the user interface and SwiftWasm for the underlying web app code.

The web app runs as a self-contained wasm that provides the entire user interface only from the wasm executable, via DOM manipulation. 

Refer to the [Tokamak repo](https://github.com/TokamakUI/Tokamak) for details.

See [here](./demo-tokamak-web-app/README.md) for details.

## libdispatch on WASI

Seven examples of libdispatch (Grand Central Dispatch) on WebAssembly, from a 20-line C program to a full-stack Swift web app. The command line examples run with WasmKit or wasmtime. The browser examples drive Dispatch from the browser event loop, and one of them uses ElementaryUI.

See [here](./demo-libdispatch-wasi/README.md) for details.
