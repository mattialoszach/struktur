# Verification status

Updated 17 September 2026. This records local evidence, not App Store approval or a guarantee of defect-free operation.

## Automated checks

- 90 tests pass with zero failures.
- Focus/notes/archive follow-up: early finish excludes paused time, preserves the linked task and notes, survives relaunch, and records only once. Pause/finish at expiry records a completed timer. Debounced note edits and checklist changes persist; unreadable saved data stays protected. Checklist toggling leaves inline examples, indentation, and links intact. Reference parsing rejects placeholders/malformed URLs. Deleting an archived space preserves tasks, notes, recurrence, event links, focus sessions, goal membership, widget identity/size, and unrelated preferences; active spaces cannot be deleted through that operation.
- Shared controls: intrinsic option widths, compact wrapping without overlap, and empty/unbounded layouts. Date fields: native action-to-binding updates, minimum day/time clamping, preservation of entered times, leap years, week-start preferences, and calendar grids/day selection across daylight-saving changes.
- Wording: personal overrides survive relaunch and export/import, reset independently, and preserve existing preferences and workspace content. Legacy workspaces use the new defaults. Whitespace, oversized imported text, Unicode characters, and unknown future wording keys are covered.
- Recurrence: selected weekdays, interval/count/until boundaries, DST, month-end behavior, all-day durations, distant-future queries, stable UID lookup, exceptions, series edits, and deletion/reference cleanup. The next-block lookup has no one-year cutoff; canceled occurrences stay canceled after editing a series.
- Goals: daily/weekly reset boundaries, configurable week starts, recurring-task families, actual assigned focus time, deduplicated references, pinned widgets, relaunch, and scoped export.
- Persistence: legacy decoding, one-time pre-migration backups, atomic saves, safe import validation/backups, unreadable-workspace protection, and invalid focus-state rejection. Single-space exports preserve moved exceptions without including another space's events.
- Reliability: a 10,000-task / 100-series save-reload-query stress check; widget packing at four widths; resize clamping and forward/backward reorder. Live resize tests cover intermediate pixel sizes for every card at four widths, including reserved gutters, canvas edges, anchored corners, and preservation of wider saved spans during vertical resizing in compact windows. Native grip events remain stable as their view moves; Escape cancels without a commit. Short month rows keep a readable minimum height.
- Apple exchange with an injected fake client: denied permissions, partial-save callbacks, retry deduplication, import ranges, and exported occurrence links. These are not live EventKit tests.
- Release packaging: universal arm64/x86_64 binary, icon/resources, privacy manifest, valid ad-hoc signature. Both binary slices declare macOS 15.0 minimum. The installed beta SDK emitted an Intel deprecation warning; this does not replace testing on an actual Intel Mac or macOS 15.
- The 16 September packaged app launched with a native window and no workspace-recovery warning. The 17 September package was rebuilt and signature-verified; its updated UI was exercised in isolated debug previews. A separate launch of the new release package was not repeated against the personal workspace.
- Distribution and live-QA scripts refuse to proceed without their explicit prerequisites. No notarization upload or store submission was performed.

- Focus session library: draft and active titles, captured note copies, early/timed finishes, clear-without-changing-history, relaunch, title/notes-only edits, deletion without recreating stale records, updated goal totals, all-history search beyond ten sessions, scoped exports/imports, and legacy records without invented note copies are covered. Titles captured from linked tasks survive task renaming/deletion. Compact `- []` and empty checklist markers render and toggle.

## Native checks

All interactive checks use temporary preview workspaces, not the personal workspace.

- Session-library follow-up: aligned timer/notes cards and full-width Write/Preview notes inspected at 1040 × 740 and 1867 × 1139. The large statistics cards and timer guidance were removed. Native title entry, start/pause/finish, clear cancellation/confirmation, reopening captured notes, renaming, saved-checkbox editing, delete cancellation, and deletion from both a history row and the saved-session editor were exercised with persisted JSON assertions. Working notes stayed separate from saved edits/deletions. Searching by note contents found and opened the expected saved session. Earlier records remain available; note snapshots cannot be recovered for sessions saved before this feature.

- Initial Focus/notes/archive follow-up: light and dark Focus pages inspected at 1040 × 740. The session-library pass above supersedes that page layout. Mouse selection and right-arrow navigation persisted the focus duration without a blue focus outline. Clicking a note checkbox persisted the checked Markdown and survived preview relaunch. Start → Pause → Finish early recorded only 2.33 seconds and cleared the timer; the page shows recent history and a saved-session message. Native clicks on valid note references opened task editors within the same window, including a second editor sheet reached from a task's notes; Cancel returned to the prior draft. Placeholder references displayed an in-app alert. The helper now routes click replay to the frontmost attached sheet and lists link controls.
- Archived-space native checks: archive, cancel deletion, restore, archive again, and confirm deletion. The sample space was removed while all ten tasks (including completed tasks) remained, with its tasks detached from the deleted space. Restore/delete controls and the empty archive were inspected in dark mode. The archive follow-up passed its test suite and universal packaging/signature check. Physical input and external launch routing from other apps remain outside this pass.

- Task creation/save/search/completion; scheduled tasks and all-day calendar blocks.
- Weekly recurring-event creation and persistence; opening an occurrence, switching to entire-series editing, and saving a new title while retaining its rule. Goal creation with a selected task reference.
- Add/expand a custom goal widget; complete a connected task and verify progress changes from 2/5 to 3/5.
- Native mouse-event replay through AppKit grips successfully resizes and reorders widgets, with persisted JSON assertions. Accessibility increment/decrement actions also change widget sizes.
- Layout refinement: held drags visibly lift and move the actual card, with neighbors reflowing and a destination placeholder. A held calendar resize grew exactly 150 × 90 points before release, moved its neighbor aside, and left saved JSON unchanged. Escape restored the original size/order. Shrink/grow releases persisted the snapped size, and relaunch restored it.
- Editing-state follow-up: Edit layout, Done, and Add widget use matching 104 × 28-point buttons in a fixed-height toolbar. Native accessibility measurements confirmed identical button positions and widget header bounds when entering and leaving editing. The editing badge, warm neutral header/resize backgrounds (without colored edit outlines), stronger handles, and subdued widget content were inspected in light and dark themes at 1040 × 740.
- Control follow-up: Today/Upcoming/Open/Completed remain fully visible and all four filters operate at 1040 × 740. Active/Archived in Spaces is centered with the New space button and switches between the expected views. A long custom task subtitle wraps without truncation. Scrolling task, goal, sidebar, and search titles no longer impose unnecessary one-/two-line limits.
- Date-field follow-up: task deadlines, project targets, event start/end fields, the Goals date, and the shared calendar popover were inspected. Calendar selection, month navigation, Today, and Done were exercised in isolated previews. Changing a task's deadline day preserved 17:00 and persisted the expected UTC date in JSON. Moving an event's start to another day retained its one-hour duration; earlier end days and Today were disabled. Both themes use the shared styling; no live Apple exchange was invoked.
- Flat option controls: calendar switching and arrow-key navigation update the persisted mode; task filters, focus duration, and Markdown Write/Preview controls remain operable. Red destructive styling and shared Save/Cancel actions were inspected in the task editor. Completed-task chart inspection confirmed the smooth descent to zero and flat zero runs without negative overshoot.
- Calendar containment: month widgets were shrunk to one cell and expanded again; widget clipping prevents content spilling beneath neighboring cards. Month rows use internal scrolling at small heights instead of collapsing over each other.
- Relaunch preserves widget IDs, order, sizes, and the added goal widget.
- Focus start/pause across pages; shared Markdown checkbox edits; calendar view switching and crowded-month-day popovers.
- Light/dark UI and compact 1040 × 740 layouts inspected, including goals and the new editors.
- Accessibility labels/actions, readable muted text, reduced-motion handling, keyboard alternatives, and explicit native drag hit areas added.
- Wording editors: single-click leaves text unchanged; double-click opens the popover; native text entry with Return or Save persists the change; Escape and Cancel discard drafts. Restoring the default requires Save, and saving a blank field resets only that heading. Over-limit input cannot be submitted. Dashboard and widget headings were exercised, with persisted JSON checks and a preview relaunch.
- Updated copy inspected in light/dark themes and at 1040 × 740, including the dashboard, tasks, spaces, goals, focus, and insights pages. Custom headings now wrap naturally rather than imposing the previous two-line truncation. Clicking outside the editor discards the draft. Calendar appointment slots and relationship-map nodes still use bounded text layouts to preserve their geometry; complete item text is available when opened.

Global synthetic pointer routing was unreliable in this environment. The verified drag and double-click checks replay native NSEvents inside a debug preview; wording entry uses the native AppKit field editor. They are not physical trackpad tests. Exhaustive native date-field keyboard entry, full VoiceOver walkthroughs, and broader device testing remain human release-QA tasks.

## External gates

1. Live Calendar/Reminders verification awaits explicit approval and macOS access. After approval, use the separate QA app via:

   ~~~sh
   ./scripts/apple-qa.sh --allow-disposable-apple-data
   ~~~

   It creates a uniquely named disposable calendar/list, checks timed/all-day events and reminders through the real exchange client, verifies retry deduplication, and removes only those QA containers. Read its final cleanup result. This pass has not run that live test.

2. No valid code-signing identity was available on this Mac. Public signing/notarization/store submission requires the owner's Apple Developer credentials, route choice, and approved release metadata. See [Distribution](Distribution.md).

3. Apple exchange currently adds new items manually. Automatic two-way synchronization was optional in the original request and remains a separate product decision; edits/deletions are not automatically propagated.

Reference: Apple's [EventKit access requirements](https://developer.apple.com/documentation/EventKit/accessing-the-event-store).
