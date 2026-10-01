# Building and testing

## Run

Requires a Swift 6.2+ toolchain and the macOS 26.4 SDK or later (for Foundation Models token counting). Development has been verified with the installed Swift 6.4 toolchain. The packaged app still targets macOS 15; Apple’s on-device assistant is enabled only on macOS 26 or later.

~~~sh
swift run Struktur
~~~

Build the local macOS application:

~~~sh
./scripts/build-app.sh
open dist/Struktur.app
~~~

The packaging script generates the icon, embeds the privacy manifest and offline math/font resources, and verifies an ad-hoc signature. Previous app builds are preserved in `dist`. Set `STRUKTUR_UNIVERSAL=1` to build both Apple Silicon and Intel slices. Public distribution requires your Apple Developer identity and approval; see [distribution instructions](Distribution.md).

## README screenshots

```sh
./scripts/capture-demos.sh
```

This builds a debug app and captures four real app views as lossless WebP images in `Documentation/Images`: three in light mode and one in dark mode. Install `cwebp` (`brew install webp`) before running it. It launches isolated sample workspaces and a simulated Assistant, with no API key, personal workspace, or Calendar/Reminders access. The UI helper needs macOS Accessibility permission. The calendar uses the debug-only `calendar-demo` fixture, which adds fictional appointments across the current week; dates follow the day of capture. Inspect the images before committing them. Set `STRUKTUR_CAPTURE_ONLY=notes-light` (or another image name from the script) to refresh one image.

## Verification

~~~sh
swift test
~~~

The suite currently has 210 checks: 206 run by default, and four require explicit opt-in for the live Apple model. Coverage includes persistence and migration, import backups, calendar recurrence and daylight-saving boundaries, task scheduling, dashboard layout, focus sessions, native live Markdown/LaTeX editing, and Assistant context, draft review, cancellation, undo, and panel positioning. The [verification log](Verification.md) records results and remaining limits.

Four opt-in tests exercise the actual Apple model on a compatible Mac using only temporary sample data (no Calendar/Reminders access):

~~~sh
STRUKTUR_TEST_APPLE_MODEL=1 swift test --filter AppleAssistantTests
~~~

Debug builds support isolated previews that never touch your personal workspace:

~~~sh
STRUKTUR_PREVIEW=1 STRUKTUR_SNAPSHOT=/tmp/struktur.png .build/debug/Struktur
STRUKTUR_PREVIEW=1 STRUKTUR_THEME=dark STRUKTUR_WIDTH=1040 STRUKTUR_HEIGHT=740 \
  STRUKTUR_SNAPSHOT=/tmp/struktur-dark.png .build/debug/Struktur
~~~

`STRUKTUR_SECTION=calendar` (or `tasks`, `projects`, `notes`, `goals`, `focus`, `insights`, `settings`) opens a specific page. `scripts/ui-check.swift` can inspect or exercise an explicitly selected preview PID through macOS Accessibility for native smoke checks.

`STRUKTUR_PREVIEW_FIXTURE=assistant-calendar` adds a temporary meeting tomorrow for assistant date checks, while `assistant-tasks` adds overdue and unscheduled task examples. `STRUKTUR_PREVIEW_FIXTURE=assistant` uses a simulated reply; `STRUKTUR_PREVIEW_ASSISTANT_DELAY_MS=5000` keeps its working state visible for animation checks. `STRUKTUR_PREVIEW_FIXTURE=completion` adds recurrence/goal examples. Reuse a printed temporary workspace with `STRUKTUR_PREVIEW_ID=<its identifier>` for relaunch checks. The UI helper supports scrolling and debug-only native mouse-event replay (`replay-drag` / `replay-resize`).

`replay-hold-drag` / `replay-hold-resize` pause before release to inspect live movement and verify that previews have not changed saved data. Use `capture-now` for the current window without resetting its size, and `replay-key escape` to cancel. Option controls can be exercised with `replay-key left` / `right` after focusing a choice.

For wording checks, use `replay-click` or `replay-double-click` with an accessibility identifier such as `wording.dashboardTitle`. `replay-text` replaces the wording editor's text through the native field editor; `replay-key return` / `escape` exercises save/cancel. These helpers only operate in explicitly launched debug previews.

Live Calendar/Reminders exchange testing requires explicit consent: `scripts/apple-qa.sh --allow-disposable-apple-data` builds a separate QA app, requests permissions, creates disposable test containers, verifies round trips, and removes only its own containers. Do not run it without approval. See [verification details and release gates](Verification.md).

[Back to the overview](../README.md)
