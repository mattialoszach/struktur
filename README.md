# Struktur

A native macOS workspace for schedules, tasks, projects, and notes.

Built in Swift 6 and SwiftUI for macOS 15+. No web view, account, analytics, or third-party dependencies.

![Struktur in light mode](Documentation/preview-light.png)

[Dark mode preview](Documentation/preview-dark.png)

## Run

Requires a Swift 6.2+ toolchain (Xcode 26+). Development has been verified with the installed Swift 6.4 toolchain.

~~~sh
swift run Struktur
~~~

Build the local macOS application:

~~~sh
./scripts/build-app.sh
open dist/Struktur.app
~~~

The packaging script generates the icon, embeds the privacy manifest, and verifies an ad-hoc signature. Previous app builds are preserved in `dist`. Set `STRUKTUR_UNIVERSAL=1` to build both Apple Silicon and Intel slices. Public distribution requires your Apple Developer identity and approval; see [distribution instructions](Documentation/Distribution.md).

## Your workspace

- Eleven widget types: day timeline, tasks, focus, deadlines, connections, momentum, daily progress, upcoming events, project goals, Markdown notes, and custom goal tracking.
- **Edit layout** switches to **Done** without changing button size or shifting the toolbar or widgets. An editing badge, warm neutral backgrounds on draggable headers and resize handles, and subdued content make the mode visible without colored outlines. Drag a header to lift and move its widget with the pointer; neighboring widgets make room and a placeholder marks the destination. Drag the bottom-right corner to resize live, then release to snap to the grid. Escape cancels the current drag. Only the final order or size is saved. The widget menu also offers exact sizes, move earlier/later, removal, and space filters for supported modules.
- Add multiple instances of a widget and pin each to a different space. Layout, size, order, appearance, and calendar preferences save automatically.
- Every widget can open in a larger view. Calendar, tasks, spaces, notes, goals, focus, and insights also have dedicated pages.
- Double-click the dashboard title, page taglines, or descriptive headings inside widgets to change their wording. The text keeps its existing styling, with no edit icon or hover decoration. Return saves; Escape or clicking outside cancels. Choose **Use default**, then Save, or save a blank field to restore the original wording. Edits persist with your workspace, including export/import, and the same widget heading is shared across instances and expanded views. Right-click → **Edit wording…** and the accessibility **Edit wording** action also open the editor.
- The starter workspace is labeled as sample content. Keep the examples or start empty in Settings → General.
- The original default dashboard upgrades to the new starter layout. Custom legacy widget selections and calendar/appearance settings are retained.

## Time, with context

The flow timeline shows actual start and end times, live countdowns, open gaps, and the final block of the day. Scheduled tasks occupy their estimated duration. A deadline is displayed as a due marker, not an invented calendar appointment.

The calendar supports day, week, month, and agenda views; custom working hours; Sunday/Monday weeks; and optional weekends. Calendar modes, task filters, appearance, focus duration, and Markdown modes share flat option controls with keyboard navigation. Their selected background identifies the active choice without a blue focus outline; calendar-popover days follow the same approach. Choices reserve room for their full labels and wrap into rows when constrained. Overlapping blocks get separate lanes, and multi-day/all-day events retain their date boundaries. Double-click an open timeline slot to create a block. Drag a task from the task list onto the calendar to schedule it. Month cells offer an add-block context menu. Calendar content stays inside its widget; short month views scroll instead of compressing date rows.

Date fields use a shared rounded surface with locale-aware native text editing and a calendar popover styled like the sidebar. Choosing a day preserves the time; minimum dates are respected. The calendar follows your Sunday/Monday preference and provides month navigation and a Today shortcut.

Spaces carry a pastel color and a heart, diamond, spade, or club symbol across the app. A shared Active/Archived selector switches between current and archived spaces. Link tasks to specific calendar blocks, track a space's goal, inspect the relationship map, and copy stable `struktur://task/UUID`, `struktur://event/UUID`, or `struktur://space/UUID` references. Global search accepts titles, notes, and identifiers. Custom headings and titles in scrolling lists wrap instead of being shortened with ellipses.

Archived spaces remain until you restore or delete them from Spaces → Archived. **Delete space…** asks for confirmation and permanently removes the space, its description, and its space goal. Tasks and their notes, calendar blocks, and focus history remain; the tasks and blocks no longer belong to that space. Linked tracking goals keep the existing tasks, and widgets filtered to the deleted space switch to all spaces. Individual tasks and blocks can be deleted in their editors.

Calendar blocks can repeat daily, weekly on selected weekdays, or monthly, with an interval, end date, occurrence count, or no end. Rules retain their time zone and wall-clock time across daylight-saving changes. Edit/delete a single occurrence or the entire series; individually edited exceptions are retained when changing a series. Stable occurrence IDs resolve without storing every future block.

The Goals page supports daily, weekly, and ongoing targets for completed tasks or recorded focus minutes. Select individual task IDs or whole spaces, including future occurrences of recurring tasks. Pin different goals to separate dashboard widgets. Expanded goal widgets expose their connected tasks. Copy `struktur://goal/UUID` references; global search also accepts full references and occurrence IDs.

## Notes library

**Notes** is a dedicated library for lecture notes, research, plans, and everyday ideas. Create a note from the sidebar, the global Create menu, or `⌥⌘N`. Notes autosave through the workspace store. Search titles, contents, or UIDs within the library or global search. Pin important notes from their actions menu.

The library is an expandable tree: click a folder to open or close its notes and subfolders (up to 32 levels). Each folder’s **…** menu creates notes/subfolders or renames, moves, and removes that folder. New notes reveal their folder path automatically. Drag a note onto a folder, or use **Move to folder** in its context/actions menu. Notes outside folders appear at the library’s top level. Pinned notes appear first within each folder; other notes stay in title order while you type. Search finds notes across closed folders. Removing a folder moves its contents to its parent. **Recently deleted** keeps notes available for restoration until you explicitly confirm permanent deletion. The selected note, folder, expanded folders, and Write/Preview mode persist.

The native **Write** editor uses ordinary text with a consistent font and line spacing. Markdown stays visible and editable; **Preview** renders headings, emphasis, code, clickable checklists, and links. **Color** (palette icon) and **Highlight** apply in both modes and show named samples of all five shades. `⌘B` and `⌘I` toggle Markdown around a selection. Changing a block style replaces its previous heading/list marker. **Insert** offers headings, lists, checklists, quotes, code blocks, dividers, web links, and a searchable picker for notes, tasks, events, spaces, and goals. Return continues a list; Return on an empty item ends it. Switching back to Write preserves its selection and text undo history. Every note has a stable `struktur://note/UUID` reference that also works from task/event/focus notes.

Write uses AppKit's native TextKit 2 editor, and the title uses a native text field. Both keep typing within the native control; the saving indicator updates independently. Sidebar navigation skips the page-transition animation, and leaving a page skips saving when the workspace is already saved. Typing updates the editor and workspace in memory immediately, without reparsing Markdown or redrawing the entire workspace for each key. Colors/highlights use AppKit's exact UTF-16 edit ranges. Delayed view updates read the current document so they cannot restore an older typing snapshot. Library/search refreshes are coalesced after typing pauses; word counting and autosave encoding/writing run off the UI thread. Autosave starts after about 350 ms of idle time and retains atomic writes. Navigation and quit flush pending changes in order; exports include the latest text immediately. See [verification evidence](Documentation/Verification.md) for measured results and remaining limits.

Use **Insert → Image from file…**, paste an image, or drop an image into Write. Images are copied into the workspace, so moving the original file does not break the note. Supported raster images are normalized to PNG at up to 2,000 pixels on the longest edge; input files must be under 30 MB. Each note supports up to 100 stored images / 50 MB. Removing image Markdown leaves the stored image available for text undo; permanent note deletion removes its images.

**Note actions → Export Markdown…** creates a new folder containing an ordinary `.md` file and the referenced local images in `assets/`. The Markdown source is preserved exactly. Colors/highlights are separate workspace metadata and do not add nonstandard syntax to that file. **Export PDF…** creates paginated A4 pages with the title, formatted text, colors, highlights, images, page numbers, and clickable links. Full-workspace JSON backups include the library, folders, images, and visual annotations; individual-space exports omit this independent library.

The editor supports common line-based Markdown: headings, emphasis, lists, quotes, checklists, fenced code, links, and inserted images. It is not a complete CommonMark or Notion block editor: tables, HTML, and advanced extensions remain source text, and complex nesting is not fully rendered. Remote images appear as labels; insert a local copy to include the image. Existing task, event, and focus note editors retain their current behavior.

## Tasks, notes, and focus

Tasks support deadlines, scheduled starts, estimated durations, priorities, daily/weekly recurrence, and open-ended work. Completing a recurring task generates a future occurrence without hiding overdue work.

Markdown supports headings, inline formatting, links, lists, quotes, and interactive checkboxes. Both `- [ ] Item` and `- [] Item` render as checkboxes. Focus notes use one full-width editor with a Write/Preview switch; other note editors can show a live preview beside the editor when there is enough room. Switch to **Preview** to click checklist boxes; they update the note text and are separate from task completion. Notes in task/event editors save with **Save**, while Cancel discards the draft. Valid Struktur links in notes open item editors inside the current window; invalid references show an in-app message. The Markdown syntax example is plain text, so clicking its example link cannot launch another app instance.

Focus notes are a working notepad, also shown in Notes widgets. Changes save locally about 350 milliseconds after typing stops, and pending edits are saved when leaving the page or quitting. **Clear notes…** clears this working text after confirmation; saved sessions keep their own copies. The Focus page uses aligned cards, a single notes editor, and a compact daily summary above the history. Notes and session history live in `workspace.json` with the rest of the workspace; Settings → Data → Reveal data folder opens that location.

The focus timer is shared across the dashboard and Focus room. **Finish early** ends a running or paused timer and saves only time actually spent focusing, excluding pauses. It leaves the linked task open; **Complete task & finish** completes that task and saves the session. Active and paused sessions survive relaunch. A timer that reaches zero records its full duration automatically. Give the session an optional title before or during the timer. When it finishes, its title and a copy of the current notes are saved with its recorded time. An untitled session uses its linked task’s name or “Focus session.”

**Saved sessions** shows the full history and searches both titles and saved notes. Click a session to read its notes, rename it, or edit its checklist; Save commits those edits and Cancel discards them. Delete a session from its row or editor after confirmation. Deletion removes that session and its note copy, updates focus totals and linked goals, and leaves the working notepad and tasks intact. Older sessions from before this feature remain accessible for their time records, but have no historical note copies; the current working notes are preserved.

Completed-task charts use a smooth piecewise monotone curve that stays between consecutive values, including flat zero runs. Destructive editor actions use red text and a subtle red background; save and completion actions use the shared primary button style.

## Data and Apple apps

Your workspace is stored atomically under the app's Application Support directory as `Struktur/workspace.json`. A sandboxed app uses its container's Application Support directory; `swift run` uses the unsandboxed directory.

Settings → Data supports full-workspace and individual-space JSON exports. Imports replace the workspace after validation and preserve a separate backup of the previous file. The first save upgrading an older workspace to schema 3 also preserves an original `workspace-before-v3-…` backup. Goals and repeat rules are included in eligible exports. An unreadable workspace is never silently overwritten.

Settings → Apple offers optional manual exchange with Apple Calendar and Reminders. Export calendar blocks in a chosen range (up to one year per exchange) and open tasks from all spaces or a selected space. Repeating blocks export as individual occurrences within that range; import calendar events from the previous 30 and next 90 days, or import reminders. Identifiers prevent duplicate imports, including recurring calendar occurrences. Successful partial exports are recorded immediately so a later permission or save failure does not cause those items to be exported twice.

This connection adds new items and preserves existing ones. It is **not automatic two-way sync**: edits and deletions are not propagated. macOS permission and an available writable calendar/list are required. No Calendar or Reminders data is read merely by opening Struktur.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘N` | New task |
| `⇧⌘N` | New calendar block |
| `⌥⌘N` | New library note |
| `⌘B` / `⌘I` | Bold / italic in the Notes Write editor |
| `⌘K` | Search notes, tasks, events, spaces, goals, and identifiers |
| `⌘T` | Today |
| Return / Escape | Save / cancel an editor |

## Verification

~~~sh
swift test
~~~

127 tests cover workspace migration, widget persistence and packing, continuous resize spacing and bounds, stable pointer tracking and cancellation, compact month rows, full-label option sizing and wrapping, date-field bindings and minimum dates, calendar grids and daylight-saving transitions, recurring tasks and calendar series, linked goals, focus pause/resume/relaunch and early/expired finishes, schedule overlap and free-time calculation, all-day boundaries, reference validation, scoped exports, import validation/backups, Apple exchange with a fake client, Markdown checkboxes and autosave, native note typing with highlights and Unicode, marked-text composition, editor undo across autosave and Preview, stale view refreshes, native redraw of highlighted edits, full-window title/body typing, compact toolbar wrapping, clean navigation without redundant saves, background autosave ordering/failures, named session note snapshots, full-history search, session editing/deletion, legacy session compatibility, archived-space deletion with retained content and references, and custom wording persistence, resets, and legacy compatibility.

Debug builds support isolated previews that never touch your personal workspace:

~~~sh
STRUKTUR_PREVIEW=1 STRUKTUR_SNAPSHOT=/tmp/struktur.png .build/debug/Struktur
STRUKTUR_PREVIEW=1 STRUKTUR_THEME=dark STRUKTUR_WIDTH=1040 STRUKTUR_HEIGHT=740 \
  STRUKTUR_SNAPSHOT=/tmp/struktur-dark.png .build/debug/Struktur
~~~

`STRUKTUR_SECTION=calendar` (or `tasks`, `projects`, `notes`, `goals`, `focus`, `insights`, `settings`) opens a specific page. `scripts/ui-check.swift` can inspect or exercise an explicitly selected preview PID through macOS Accessibility for native smoke checks.

`STRUKTUR_PREVIEW_FIXTURE=completion` adds recurrence/goal examples. Reuse a printed temporary workspace with `STRUKTUR_PREVIEW_ID=<its identifier>` for relaunch checks. The UI helper supports scrolling and debug-only native mouse-event replay (`replay-drag` / `replay-resize`).

`replay-hold-drag` / `replay-hold-resize` pause before release to inspect live movement and verify that previews have not changed saved data. Use `capture-now` for the current window without resetting its size, and `replay-key escape` to cancel. Option controls can be exercised with `replay-key left` / `right` after focusing a choice.

For wording checks, use `replay-click` or `replay-double-click` with an accessibility identifier such as `wording.dashboardTitle`. `replay-text` replaces the wording editor's text through the native field editor; `replay-key return` / `escape` exercises save/cancel. These helpers only operate in explicitly launched debug previews.

Live Apple testing requires explicit consent: `scripts/apple-qa.sh --allow-disposable-apple-data` builds a separate QA app, requests permissions, creates disposable test containers, verifies round trips, and removes only its own containers. Do not run it without approval. See [verification details and release gates](Documentation/Verification.md).
