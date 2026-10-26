#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
.build/release/Birding --export-shared "$ROOT/shared"
.build/release/Birding --export-icon "$ROOT/Assets"
