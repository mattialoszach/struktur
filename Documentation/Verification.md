# Redesign verification

Verified locally on 16 September 2026 with Swift 6.4 on macOS.

## Automated checks

`swift test`: 25 tests, zero failures. Coverage includes legacy workspace migration and identifier preservation, widget persistence and non-overlapping packing, recurrence, focus sessions across relaunch, calendar interval math, all-day editing, Markdown checklists, and safe import/export behavior.

`scripts/build-app.sh`: release compilation, icon/resource packaging, and ad-hoc signature verification. Previous local application bundles are preserved in `dist`.

## Native interaction checks

Interactive checks ran in isolated sample workspaces, not the personal workspace:

- Create and save a task, then find it through global search.
- Complete tasks and observe connected counts update.
- Create a scheduled task and an all-day calendar block.
- Start and pause the shared focus timer across pages.
- Change a widget's exact size through its menu; add and expand widgets.
- Edit Markdown checkboxes and observe the same note in different modules.
- Switch calendar views and open a crowded month day's full item list.
- Inspect the light/dark dashboards and compact 1040 × 740 layouts, editors, focus room, calendar, and general settings.

Widget packing is covered by tests across four widths. Pointer-driven dragging and resize handles still warrant broader hands-on testing across trackpads and display scales.

## Before public distribution

- Verify Calendar and Reminders exchange with explicit macOS permission and a disposable calendar/list. No live EventKit data exchange was performed during this pass.
- The Apple connection is manual new-item import/export, not automatic two-way synchronization.
- Configure Apple Developer signing, provisioning, notarization or App Store submission as appropriate. The generated local bundle is ad-hoc signed, not a public release.
- Run broader usability and accessibility testing, including VoiceOver and different display sizes. Automated coverage and local smoke checks do not replace release QA.
