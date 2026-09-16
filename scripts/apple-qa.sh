#!/bin/zsh
set -euo pipefail
SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
cd "$PROJECT_DIR"
if [[ "${1:-}" != "--allow-disposable-apple-data" ]]; then
    print -u2 "This test creates and removes a disposable Apple calendar/list and their QA records."
    print -u2 "After explicit approval, run: scripts/apple-qa.sh --allow-disposable-apple-data"
    exit 2
fi
STRUKTUR_QA=1 STRUKTUR_BUILD_CONFIGURATION=debug ./scripts/build-app.sh
STRUKTUR_PREVIEW=1 STRUKTUR_APPLE_QA=1 STRUKTUR_ALLOW_DISPOSABLE_APPLE_DATA=1 \
    "$PROJECT_DIR/dist/Struktur-QA.app/Contents/MacOS/Struktur"
