# Using Struktur

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

The calendar supports day, week, month, and agenda views; custom working hours; Sunday/Monday weeks; and optional weekends. Calendar modes, task filters, appearance, and focus duration share flat option controls with keyboard navigation. Tasks opens to **Today**, which shows work due or scheduled today plus overdue tasks. **Upcoming** shows unfinished work due or scheduled after today, while **Open** shows every unfinished task. Their selected background identifies the active choice without a blue focus outline; calendar-popover days follow the same approach. Choices reserve room for their full labels and wrap into rows when constrained. Overlapping blocks get separate lanes, and multi-day/all-day events retain their date boundaries. Double-click an open timeline slot to create a block. Drag a task from the task list onto the calendar to schedule it. Month cells offer an add-block context menu. Calendar content stays inside its widget; short month views scroll instead of compressing date rows.

Date fields use a shared rounded surface with locale-aware native text editing and a calendar popover styled like the sidebar. Choosing a day preserves the time; minimum dates are respected. The calendar follows your Sunday/Monday preference and provides month navigation and a Today shortcut.

Spaces carry a pastel color and a heart, diamond, spade, or club symbol across the app. A shared Active/Archived selector switches between current and archived spaces. Link tasks to specific calendar blocks, track a space's goal, inspect the relationship map, and copy stable `struktur://task/UUID`, `struktur://event/UUID`, or `struktur://space/UUID` references. Global search accepts titles, notes, and identifiers. Custom headings and titles in scrolling lists wrap instead of being shortened with ellipses.

Archived spaces remain until you restore or delete them from Spaces → Archived. **Delete space…** asks for confirmation and permanently removes the space, its description, and its space goal. Tasks and their notes, calendar blocks, and focus history remain; the tasks and blocks no longer belong to that space. Linked tracking goals keep the existing tasks, and widgets filtered to the deleted space switch to all spaces. Individual tasks and blocks can be deleted in their editors.

Calendar blocks can repeat daily, weekly on selected weekdays, or monthly, with an interval, end date, occurrence count, or no end. Rules retain their time zone and wall-clock time across daylight-saving changes. Edit/delete a single occurrence or the entire series; individually edited exceptions are retained when changing a series. Stable occurrence IDs resolve without storing every future block.

The Goals page supports daily, weekly, and ongoing targets for completed tasks or recorded focus minutes. Select individual task IDs or whole spaces, including future occurrences of recurring tasks. Pin different goals to separate dashboard widgets. Expanded goal widgets expose their connected tasks. Copy `struktur://goal/UUID` references; global search also accepts full references and occurrence IDs.

## Notes library

**Notes** is a dedicated library for lecture notes, research, plans, and everyday ideas. Create a note from the sidebar, the global Create menu, or `⌥⌘N`. Notes autosave through the workspace store. Search titles, contents, or UIDs within the library or global search. Pin important notes from their actions menu.

The library is an expandable tree: click a folder to open or close its notes and subfolders (up to 32 levels). Each folder’s **…** menu creates notes/subfolders or renames, moves, and removes that folder. New notes reveal their folder path automatically. Drag a note onto a folder, or use **Move to folder** in its context/actions menu. Notes outside folders appear at the library’s top level. Pinned notes appear first within each folder; other notes stay in title order while you type. Search finds notes across closed folders. Removing a folder moves its contents to its parent. **Recently deleted** keeps notes available for restoration until you explicitly confirm permanent deletion. The selected note, folder, and expanded folders persist.

The native editor formats Markdown as you type in a single surface. Click the title or body to write; Escape leaves the field and hides the caret until you click it again. Completed headings, emphasis, lists, code, checklists, links, and images appear in place. Syntax is revealed when you move into a formatted span. **Color** and **Highlight** apply to selected text and offer five named shades. `⌘B` and `⌘I` toggle formatting; **Insert** offers block styles, equations, images, web links, and workspace links. **Formulas** inserts common LaTeX examples with an editable part selected. Return continues a list; Return on an empty item ends it. Click a checkbox, or press `⌘Return` on its line, to toggle it. `⌘Click` opens links. Every note retains its stable `struktur://note/UUID` reference.

Write inline math as `$E = mc^2$` or `\(E = mc^2\)`. For display math use `$$…$$` or `\[…\]`, including multiple lines. Fractions, roots, Greek letters, sums, integrals, matrices, and other supported LaTeX math commands render offline. Click an equation to reveal its source; its result updates underneath while you edit, then returns inline when you leave. Incomplete or unsupported expressions stay editable as source. Rendering is bounded to 4,096 UTF-16 units, 32 levels of brace nesting, and 256 commands per expression. This is math-mode LaTeX, not a TeX document compiler.

The editor uses AppKit TextKit 2 with incremental paragraph parsing and native viewport layout. Presentation changes never replace the underlying source text, so selections, Unicode, undo, and annotation ranges retain their original coordinates. A checkpoint index limits ordinary reparsing to affected paragraphs and propagates fence changes only until parser state converges. Plain edits in oversized paragraphs reuse existing styles when syntax cannot change. Equation results are cached and rasterized once; scrolling does not invoke the math parser. Native typing updates the canonical workspace immediately without publishing every keystroke across the window. Library refresh, word count, and autosave are coalesced after typing pauses; saves retain atomic writes and unreadable-data protection. Navigation and quit flush pending edits; exports include the latest source. See [verification evidence](Verification.md) for measured performance and remaining limits.

Use **Insert → Image from file…**, paste an image, or drop an image into the note. Images are copied into the workspace, so moving the original file does not break the note. Supported raster images are normalized to PNG at up to 2,000 pixels on the longest edge; input files must be under 30 MB. Each note supports up to 100 stored images / 50 MB. Removing image Markdown leaves the stored image available for text undo; permanent note deletion removes its images.

**Note actions → Export Markdown…** creates a new folder containing an ordinary `.md` file and the referenced local images in `assets/`. The Markdown source is preserved exactly. Colors/highlights are separate workspace metadata and do not add nonstandard syntax to that file. **Export PDF…** creates paginated A4 pages with the title, formatted text, colors, highlights, images, equations, page numbers, and clickable links. Full-workspace JSON backups include the library, folders, images, and visual annotations; individual-space exports omit this independent library.

The editor supports common line-based Markdown: headings, emphasis, lists, quotes, checklists, fenced code, links, and inserted images. It is not a complete CommonMark or Notion block editor: tables, HTML, and advanced extensions remain source text, and complex nesting is not fully rendered. Remote image syntax stays as source; insert a local copy to include the image. Focus, task/event notes, and dashboard notes share the live editor; stored image insertion and selection colors belong to the Notes library.

## Tasks, notes, and focus

Tasks support deadlines, scheduled starts, optional duration estimates, priorities, daily/weekly recurrence, and open-ended work. Unscheduled tasks can omit an estimate. Placing a task on the calendar assigns a 30-minute estimate when none exists so its end time and free-time calculations remain clear. Completing a recurring task generates a future occurrence without hiding overdue work.

Focus, saved sessions, task/event drafts, and dashboard notes use the same live Markdown and LaTeX surface without a Write/Preview switch. Both `- [ ] Item` and `- [] Item` render as clickable checkboxes; note checklists remain separate from tasks. Notes in task/event editors save with **Save**, while Cancel discards the draft. Valid Struktur links open item editors inside the current window; invalid references show an in-app message.

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
| `⌘B` / `⌘I` | Bold / italic in a notes editor |
| `⌘K` | Search notes, tasks, events, spaces, goals, and identifiers |
| `⌘T` | Today |
| `⌘J` | Open / close Assistant |
| Return / Shift-Return | Send an Assistant message / insert a new line |
| Return / Escape | Save / cancel an editor |


[Back to the overview](../README.md)
