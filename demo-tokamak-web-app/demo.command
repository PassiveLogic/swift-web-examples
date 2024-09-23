#!/bin/bash

# Change dir to the dir containing this script
cd "$(dirname "$0")"

set -o pipefail -o errexit

# NOTE: To use this script, first run:
# brew install swiftwasm/tap/carton

carton dev
