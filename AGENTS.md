# Struktur

Native macOS organizer for students and young professionals. Swift 6.2+, SwiftUI, EventKit; macOS 15+. Keep it native and dependency-light.

## Product & design

- Prioritize exceptional usability and working interactions over decorative polish.
- Reuse `DesignSystem.swift`: warm neutrals, consistent pastels, serif headings, and heart/diamond/spade/club symbols. Support system, light, and dark appearance.
- Keep the dashboard modular: widget order, size, filters, and view preferences must persist.
- Clearly distinguish scheduled work from deadlines; show end times, overlaps, free time, and project/task relationships without clutter.

## Implementation & safety

- App code: `Sources/Struktur`; tests: `Tests/StrukturTests`; packaging: `Distribution` and `scripts`.
- Route persistent changes through `WorkspaceStore`. Preserve Codable compatibility, stable UUID references, and existing user preferences.
- Preserve atomic saves, import validation/backups, and protection against overwriting unreadable data.
- Preserve unrelated worktree changes. Never replace the personal workspace with sample data for testing.
- Apple exchange is currently manual new-item import/export, not two-way sync. Obtain explicit approval before tests that modify live Calendar/Reminders data.

## Verification

- Run `swift test` after behavior changes; add regression tests for fixes.
- Package with `./scripts/build-app.sh`; output is `dist/Struktur.app`. Local ad-hoc signing is not App Store release signing.
- For isolated native UI checks: `swift build`, then `STRUKTUR_PREVIEW=1 STRUKTUR_SNAPSHOT=/tmp/struktur-preview.png .build/debug/Struktur`.
- Check both themes and compact 1040 × 740 layouts. Exercise changed interactions, not just screenshots; `scripts/ui-check.swift` supports native smoke checks.
- Keep `README.md` and `Documentation/Verification.md` accurate. Report implemented, tested, and unverified work separately.

## Open work

Recurring calendar series and UID-linked goals are implemented. Remaining gates: consented live Apple exchange testing, broader hardware/VoiceOver QA, developer signing credentials, and owner-approved distribution/submission. Automatic two-way sync remains an optional product decision; current exchange is manual. Consult Documentation/Verification.md for evidence. Do not claim launch readiness solely because unit tests pass.
