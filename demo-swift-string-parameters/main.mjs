// File name: main.mjs

// ================== Imports =======================

import { WASI, File, OpenFile, ConsoleStdout } from "@bjorn3/browser_wasi_shim";
import { SwiftRuntime } from "javascript-kit-swift"
import fs from "fs/promises";

// ================== Load Wasm Instance =======================

// Instantiate a new WASI Instance
// See https://github.com/bjorn3/browser_wasi_shim/ for more detail about constructor options

let wasi = new WASI([], [],
    [
        new OpenFile(new File([])), // stdin
        ConsoleStdout.lineBuffered(msg => console.log(`[WASI stdout] ${msg}`)),
        ConsoleStdout.lineBuffered(msg => console.warn(`[WASI stderr] ${msg}`)),
    ],
    { debug: false }
);

// Read in wasm file bytes
const wasmBytes = await fs.readFile("lib.wasm");

// Set up Swift JavaScriptKit
let swift = new SwiftRuntime();

// Instantiate the WebAssembly file
const { instance } = await WebAssembly.instantiate(wasmBytes, {
    wasi_snapshot_preview1: wasi.wasiImport,
    javascript_kit: swift.wasmImports
});

// Set the WebAssembly instance to the Swift Runtime
swift.setInstance(instance);

// Initialize the instance by following WASI reactor ABI
wasi.initialize(instance);

// Start Swift main function (if defined)
swift.main()


// ================== Use Wasm Instance =======================

console.log("🥁🥁🥁🥁🥁🥁🥁🥁🥁 - Start - 🥁🥁🥁🥁🥁🥁🥁🥁🥁")

// 1

// Call Swift function that populates the string to JS memory
const getStringFromSwiftFn = instance.exports.getStringFromSwift;
getStringFromSwiftFn() // ℹ️ String passed from Swift to JS here

// 3

// Grab the string sent from Swift and log it to console
const messageFromSwift = globalThis.messageFromSwift
console.log(messageFromSwift)

// 4

// Set up closure to send string to Swift
const installSwiftMessengerClosureFn = instance.exports.installSwiftMessengerClosure;
installSwiftMessengerClosureFn()

// 6

// Send string to Swift
const swiftMessenger = globalThis.swiftMessenger
swiftMessenger("Hello From JS!") // ℹ️ String passed from JS to Swift here

console.log("✅✅✅✅✅✅✅✅✅ - Finish - ✅✅✅✅✅✅✅✅✅")