#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT/ThirdParty/mediaremote-adapter"
BUILD_DIR="${MRA_BUILD_DIR:-$ROOT/.build/mediaremote-adapter}"
ARCHS="${1:-$(uname -m)}"
CMAKE_ARCHS="${ARCHS// /;}"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"

if [ ! -f "$SOURCE_DIR/CMakeLists.txt" ]; then
    echo "MediaRemote adapter source is missing: $SOURCE_DIR" >&2
    exit 1
fi

cmake \
    -S "$SOURCE_DIR" \
    -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$CMAKE_ARCHS" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    >/dev/null

cmake --build "$BUILD_DIR" --target MediaRemoteAdapter --parallel >/dev/null

echo "$BUILD_DIR"
