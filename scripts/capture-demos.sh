#!/bin/zsh
# Capture the real UI using disposable sample workspaces. Requires macOS Accessibility
# access for the UI helper. No personal workspace, API key, or Apple exchange is used.
set -euo pipefail
cd "${0:A:h:h}"
swift build
STRUKTUR_CAPTURE_TEMP=$(mktemp -d /tmp/struktur-demos.XXXXXX)
STRUKTUR_CAPTURE_PID=""
trap 'if [[ -n "$STRUKTUR_CAPTURE_PID" ]]; then kill "$STRUKTUR_CAPTURE_PID" 2>/dev/null || true; fi; rm -rf "$STRUKTUR_CAPTURE_TEMP"' EXIT
swiftc scripts/ui-check.swift -o "$STRUKTUR_CAPTURE_TEMP/ui-check"
mkdir -p Documentation/Images

capture() {
  local name="$1" theme="$2" section="$3" fixture="$4" width="$5" height="$6"
  local snapshot="$STRUKTUR_CAPTURE_TEMP/$name.png"
  STRUKTUR_PREVIEW=1 STRUKTUR_THEME="$theme" STRUKTUR_SECTION="$section" \
    STRUKTUR_PREVIEW_FIXTURE="$fixture" STRUKTUR_PREVIEW_ASSISTANT_DELAY_MS=10000 \
    STRUKTUR_WIDTH="$width" STRUKTUR_HEIGHT="$height" STRUKTUR_SNAPSHOT="$snapshot" \
    .build/debug/Struktur > "$STRUKTUR_CAPTURE_TEMP/$name.log" 2>&1 &
  STRUKTUR_CAPTURE_PID=$!
  for attempt in {1..100}; do
    [[ -s "$snapshot" ]] && break
    kill -0 "$STRUKTUR_CAPTURE_PID"
    sleep 0.1
  done
  [[ -s "$snapshot" ]] || { print -u2 "No snapshot for $name"; return 1; }
  case "$section" in
    calendar) "$STRUKTUR_CAPTURE_TEMP/ui-check" "$STRUKTUR_CAPTURE_PID" press Week ;;
    notes) "$STRUKTUR_CAPTURE_TEMP/ui-check" "$STRUKTUR_CAPTURE_PID" press Preview ;;
  esac
  if [[ "$fixture" == assistant ]]; then
    "$STRUKTUR_CAPTURE_TEMP/ui-check" "$STRUKTUR_CAPTURE_PID" press Assistant
    "$STRUKTUR_CAPTURE_TEMP/ui-check" "$STRUKTUR_CAPTURE_PID" replay-text 'Help me plan a study session for tomorrow.'
    "$STRUKTUR_CAPTURE_TEMP/ui-check" "$STRUKTUR_CAPTURE_PID" replay-key return
  fi
  sleep 1
  "$STRUKTUR_CAPTURE_TEMP/ui-check" "$STRUKTUR_CAPTURE_PID" capture-now
  cp "$snapshot" "Documentation/Images/$name.png"
  kill "$STRUKTUR_CAPTURE_PID"
  wait "$STRUKTUR_CAPTURE_PID" 2>/dev/null || true
  STRUKTUR_CAPTURE_PID=""
  print "Saved Documentation/Images/$name.png"
}

capture dashboard-light light overview '' 1460 1060
capture calendar-light light calendar calendar-demo 1460 980
capture notes-light light notes notes 1460 980
capture assistant-dark dark overview assistant 1280 820
