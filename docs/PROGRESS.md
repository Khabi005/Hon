# Hon — Project Implementation Progress

## Status Legend
- ⏳ Pending
- 🔄 In Progress
- ✅ Completed

## Phases

### Phase 0 — Validate the Technical Foundation
- [✅] Toolchain verified: Flutter 3.41.2 (Channel stable, Dart 3.11.0, DevTools 2.54.1), Android SDK 36.1.0, Java 21.0.12.1.
- [✅] Selected compatible stable dependency versions (flutter_riverpod, shared_preferences, archive, xml, html, file_picker, google_fonts, crypto, uuid, pdfx).
- [✅] Validated EPUB parser engine with valid EPUB 3 fixture (`assets/fixtures/pride_and_prejudice.epub`), verified container.xml, content.opf, manifest, spine, and chapter XHTML extraction.
- [✅] Validated PDF reader integration with `pdfx` (page controller, pinch zoom, page jump, saved location).
- [✅] Validated Storage Access Framework / File Picker pipeline with staging and SHA-256 duplicate detection.
- [✅] Validated `NovelSource` runtime contract and downloader state machine.

### Phase 1 — Establish Visual Specification & Branding
- [✅] Master 本 / Hon calligraphy logo and Apple Books iOS 18 reference screenshots added to `assets/branding/` and `docs/references/`.
- [✅] Generated Android adaptive launcher icons (foreground 432x432, light & dark backgrounds, compact square 512x512 kanji, and monochrome icon).
- [✅] Configured `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` and density folders (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi).
- [✅] Defined complete color tokens and iOS 18 frosted glass effects (`lib/app/theme/hon_colors.dart`, `lib/shared/widgets/frosted_glass.dart`).
- [✅] Defined 6 reader themes from reference Image 4: **Original**, **Quiet**, **Paper**, **Bold**, **Calm**, **Focus** (`lib/app/theme/reader_theme.dart`).
- [✅] Defined Apple Books typography scale with Newsreader serif headings and San Francisco body (`lib/app/theme/hon_typography.dart`).

### Phase 2 — Build the App Shell
- [✅] Initialized Flutter project and configured Git version control.
- [✅] Set up Riverpod state management and reactive database notification stream (`lib/app/bootstrap/providers.dart`).
- [✅] Implemented Apple Books iOS 18 bottom-tab scaffold with frosted glass blur, 5 tabs (Home, Library, Browse, Downloads, Search) with tab state preservation via `IndexedStack`.
- [✅] Built tactile book cover widget with realistic 3D book spine crease/shadow and fallback cover styling (`lib/shared/widgets/book_cover_widget.dart`).
- [✅] Built Apple Books ornate flourish divider (`lib/shared/widgets/ornate_divider.dart`).
- [✅] Seeded local fixtures for *Pride and Prejudice*, *Good Material*, *First Lie Wins*, and *War and Peace*.

### Phase 3 — Local Library & File Imports
- [✅] Persistent database service storing Books, LibraryEntries, ReadingProgress, and DownloadJobs.
- [✅] Import pipeline: File picker -> Copy to staging -> Readability check -> Metadata & Cover extraction -> SHA-256 hash deduplication -> Move to permanent storage -> Commit book and library records -> Staging cleanup.
- [✅] Grid mode and List mode view toggle.
- [✅] Filter chips (All, EPUBs, PDFs, Finished).

### Phase 4 — EPUB & PDF Readers
- [✅] Reader screen matching reference Image 3:
  - Top header: jump-back button with previous page count ("372"), chapter countdown ("9 pages left in chapter"), circular close (X) button.
  - Centered chapter title with ornate decorative flourish divider.
  - Jane Austen paragraph typography: indented first lines, comfortable line height (1.65x), balanced margins, justified text.
  - Bottom bar: page progress ("395 of 691") and menu button opening Themes & Settings sheet.
- [✅] Themes & Settings bottom sheet matching reference Image 4:
  - Font size adjuster pill `[ A | A ]`.
  - Layout toggle (Paginated vs Continuous Vertical Scroll).
  - Contrast quick invert toggle.
  - Brightness slider with sun glyphs.
  - 2x3 grid of 6 themes (Original, Quiet, Paper, Bold, Calm, Focus).
  - Customize sub-sheet for Font Family (Georgia, New York, San Francisco, Palatino), Line Spacing, and Justification switch.
- [✅] PDF reader with page controller, zoom, and page progress tracking.

### Phase 5 — Online Sources & Novels
- [✅] Novel discovery and browse catalog with source selector.
- [✅] Novel details view: cover, author, synopsis, and chapter list.
- [✅] Seamless chapter reading in reader view.

### Phase 6 — Downloads & Library Prompt
- [✅] Implemented exact Section 5 download and library prompt behavior:
  - Title: "Add to Library?"
  - Message: "Add \"{novel title}\" to your library to find it easily and check for new chapters."
  - Actions: "Add to Library" · "Not Now"
  - Dismissing behaves as "Not Now".
  - Choosing "Not Now" proceeds with download and suppresses repeat prompts for that novel during current app session.
  - Choosing "Add to Library" adds novel to library and proceeds with download.
  - Rechecks library membership immediately before prompt.
  - Downloaded novels outside library remain accessible in Downloads and Reading History.
  - Removing novel from library does NOT delete downloads; deleting downloads does NOT remove library membership.
- [✅] Persistent download queue with active downloads badge on Downloads tab.

### Phase 7 & 8 — Verification & Packaging
- [✅] Unit test suite covering Section 5 download/library rules and Section 6 reader themes.
- [✅] EPUB parser unit test verifying Pride and Prejudice fixture.
- [✅] Widget test verifying 5-tab navigation scaffold.
- [✅] Native Linux build verified (`✓ Built build/linux/x64/debug/bundle/hon`).
- [✅] Android APK built successfully (`✓ Built build/app/outputs/flutter-apk/app-debug.apk`, 152 MB).
