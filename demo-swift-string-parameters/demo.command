#!/bin/bash

# cd to the directory containing this script
cd "$(dirname "$0")"

set -o pipefail -o errexit

# =============== Prerequisites ==============
# 1. Install Xcode
# 2. Install command line tools: `xcode-select --install`

# =============== Begin Script Toolchain Setup ==============

# Install Node.js version 22
if ! command -v nvm &> /dev/null
then
   echo "nvm was not installed. Installing nvm and node version 22"
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
   export NVM_DIR="$HOME/.nvm"
   [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
   nvm install 22
   node -v
fi

echo "Beginning Swift version: $(swift --version)"
echo "Beginning Node version: $(node -v)" # Should be 22.x.x

# =============== Build Wasm ==============

# Clean up old builds
rm lib.wasm || true # ignore errors for this command

# Install third party npm dependencies used by main.mjs
npm install @bjorn3/browser_wasi_shim --save
npm install javascript-kit-swift --save

# Build wasm
echo "🔨 Building wasm…"
# swift run carton bundle --no-content-hash # optimized build
swift run carton bundle --no-content-hash --debug-info --wasm-optimizations none # fast build
echo "Wasm built ✅"

# Copy wasm to same directory as main.mjs
#
# Carton's build folder is "Bundle"
#
# The name of the .wasm file matches
# the name of the executableTarget in Package.swift.
cp ./Bundle/Demo.wasm lib.wasm

# =============== Run Wasm from Node.js ==============

# Run the wasm using Node.js
echo "🥁 Calling wasm from js…"
node main.mjs

