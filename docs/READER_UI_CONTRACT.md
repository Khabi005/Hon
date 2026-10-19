# Shared reader interface

Reference: the user's downloaded-novel reader. Rendering engines stay format-specific.

- Header: previous location at left, remaining chapters/pages in the middle, circular close at right.
- Footer: chapter/page count centered, Aa menu on the right. Progress opens contents or page jump.
- Menu: Contents, Search Book (Go to Page for PDF), Themes & Settings, then relevant sharing, orientation, layout and bookmark actions.
- Appearance: A/A text sizing for reflowable text, layout toggle, brightness where supported, six named theme cards, and Customize for real font families and spacing.
- Contents: Chapters/Pages and Bookmarks. No nonfunctional Highlights tab.
- EPUB: original Readium publication resources, links and text selection, semantic locators, fixed-layout capability gate.
- PDF: fixed page renderer, real page navigation and zoom, six paper/ink tone mappings. No ineffective font picker or quote-selection action.
- Font choices: Newsreader, Literata, System Sans, Lora, Libre Baskerville. Persisted enum IDs are retained for old preferences; labels describe the actual typefaces. Font assets and licenses ship offline.
- Native EPUB implements the same control placement and sheet/menu conventions. Flutter PDF and downloaded novels use shared ReaderHeader/ReaderFooter, ReaderMenuPopup and ThemesSettingsSheet widgets.

## Phase 1 polish

- Reflowable appearance settings include a true font preview, line spacing, margins, paragraph spacing and first-line indent. Spacing sliders commit at release.
- Flutter controls slide without relayout and respect Reduce Motion; hidden controls are excluded from touch/accessibility.
- Appearance and Customize are height-bounded, scrollable sheets with larger-text support. Native EPUB follows the same preview and spacing conventions.
- Downloaded-book Search scans saved passages in a worker isolate on submission and includes unopened local chapters.

## Acceptance boundary

Local renders cover Home light/dark and the Flutter appearance sheet. JVM tests and compilation cover source contracts and native API integration. Touch behavior, Readium font rendering, PDF zoom/filters and smoothness still need the user's phone check. Release performance is not claimed as measured FPS.
