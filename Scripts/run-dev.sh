#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-debug}" "$ROOT/Scripts/build-app.sh"
open "$ROOT/dist/TouchingBar.app"
