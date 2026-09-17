# Verification status

Updated 17 September 2026. This records local evidence, not App Store approval or a guarantee of defect-free operation.

## Automated checks

- 57 tests pass with zero failures.
- Wording: personal overrides survive relaunch and export/import, reset independently, and preserve existing preferences and workspace content. Legacy workspaces use the new defaults. Whitespace, oversized imported text, Unicode characters, and unknown future wording keys are covered.
- Recurrence: selected weekdays, interval/count/until boundaries, DST, month-end behavior, all-day durations, distant-future queries, stable UID lookup, exceptions, series edits, and deletion/reference cleanup. The next-block lookup has no one-year cutoff; canceled occurrences stay canceled after editing a series.
- Goals: daily/weekly reset boundaries, configurable week starts, recurring-task families, actual assigned focus time, deduplicated references, pinned widgets, relaunch, and scoped export.
- Persistence: legacy decoding, one-time pre-migration backups, atomic saves, safe import validation/backups, unreadable-workspace protection, and invalid focus-state rejection. Single-space exports preserve moved exceptions without including another space's events.
- Reliability: a 10,000-task / 100-series save-reload-query stress check; widget packing at four widths; resize clamping and forward/backward reorder.
- Apple exchange with an injected fake client: denied permissions, partial-save callbacks, retry deduplication, import ranges, and exported occurrence links. These are not live EventKit tests.
- Release packaging: universal arm64/x86_64 binary, icon/resources, privacy manifest, valid ad-hoc signature. Both binary slices declare macOS 15.0 minimum. The installed beta SDK emitted an Intel deprecation warning; this does not replace testing on an actual Intel Mac or macOS 15.
- The 16 September packaged app launched with a native window and no workspace-recovery warning. The 17 September package was rebuilt and signature-verified; its updated UI was exercised in isolated debug previews. A separate launch of the new release package was not repeated against the personal workspace.
- Distribution and live-QA scripts refuse to proceed without their explicit prerequisites. No notarization upload or store submission was performed.

## Native checks

All interactive checks use temporary preview workspaces, not the personal workspace.

- Task creation/save/search/completion; scheduled tasks and all-day calendar blocks.
- Weekly recurring-event creation and persistence; opening an occurrence, switching to entire-series editing, and saving a new title while retaining its rule. Goal creation with a selected task reference.
- Add/expand a custom goal widget; complete a connected task and verify progress changes from 2/5 to 3/5.
- Native mouse-event replay through AppKit grips successfully resizes and reorders widgets, with persisted JSON assertions. Accessibility increment/decrement actions also change widget sizes.
- Relaunch preserves widget IDs, order, sizes, and the added goal widget.
- Focus start/pause across pages; shared Markdown checkbox edits; calendar view switching and crowded-month-day popovers.
- Light/dark UI and compact 1040 × 740 layouts inspected, including goals and the new editors.
- Accessibility labels/actions, readable muted text, reduced-motion handling, keyboard alternatives, and explicit native drag hit areas added.
- Wording editors: single-click leaves text unchanged; double-click opens the popover; native text entry with Return or Save persists the change; Escape and Cancel discard drafts. Restoring the default requires Save, and saving a blank field resets only that heading. Over-limit input cannot be submitted. Dashboard and widget headings were exercised, with persisted JSON checks and a preview relaunch.
- Updated copy inspected in light/dark themes and at 1040 × 740, including the dashboard, tasks, spaces, goals, focus, and insights pages. Long custom headings stay within two lines; excess text is truncated in place and remains available in the editor. Clicking outside the editor discards the draft.

Global synthetic pointer routing was unreliable in this environment. The verified drag and double-click checks replay native NSEvents inside a debug preview; wording entry uses the native AppKit field editor. They are not physical trackpad tests. Full VoiceOver walkthroughs and broader device testing remain human release-QA tasks.

## External gates

1. Live Calendar/Reminders verification awaits explicit approval and macOS access. After approval, use the separate QA app via:

   ~~~sh
   ./scripts/apple-qa.sh --allow-disposable-apple-data
   ~~~

   It creates a uniquely named disposable calendar/list, checks timed/all-day events and reminders through the real exchange client, verifies retry deduplication, and removes only those QA containers. Read its final cleanup result. This pass has not run that live test.

2. No valid code-signing identity was available on this Mac. Public signing/notarization/store submission requires the owner's Apple Developer credentials, route choice, and approved release metadata. See [Distribution](Distribution.md).

3. Apple exchange currently adds new items manually. Automatic two-way synchronization was optional in the original request and remains a separate product decision; edits/deletions are not automatically propagated.

Reference: Apple's [EventKit access requirements](https://developer.apple.com/documentation/EventKit/accessing-the-event-store).
