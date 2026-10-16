# Hon — Project Implementation Progress

## Status Legend
- ⏳ Pending
- 🔄 In Progress
- ✅ Completed

## Phases

### Phase 0 — Validate the Technical Foundation
- [🔄] Inspect Flutter, Android SDK, Java, Gradle toolchain (FVM installing stable SDK)
- [⏳] Select compatible stable dependency versions
- [⏳] Validate EPUB reader integration, typography presets, locators
- [⏳] Validate PDF rendering integration and page navigation
- [⏳] Validate Android file import pipeline (EPUB & PDF)
- [⏳] Validate Source runtime contract & downloader state machine

### Phase 1 — Establish Visual Specification & Branding
- [✅] Import approved 本 / Hon master logo & reference screenshots
- [⏳] Generate Android adaptive launcher icons (foreground, background, monochrome)
- [⏳] Define color palettes, theme tokens (Original, Quiet, Paper, Bold, Calm, Focus)
- [⏳] Define Apple Books iOS 18 typography scale, card geometry, sheet styling

### Phase 2 — Build the App Shell
- [⏳] Initialize Flutter project & Git repository
- [⏳] Configure Riverpod, routing with preserved tab state
- [⏳] Implement 5-tab bottom navigation (Home, Library, Browse, Downloads, Search)
- [⏳] Implement Apple Books style header & toolbar (with Settings action)
- [⏳] Wire initial screens with rich local fixture data

### Phase 3 — Local Library & File Imports
- [⏳] Drift SQLite database schema (Books, LibraryEntries, Collections, Chapters, Downloads, Progress)
- [⏳] File picker integration for EPUB and PDF
- [⏳] Metadata extraction (title, author, description, cover image)
- [⏳] Content hash deduplication & staging storage
- [⏳] Library grid / list toggles, sorting, collections, search

### Phase 4 — EPUB & PDF Readers
- [⏳] EPUB / Web novel reader: reflowable pagination & continuous scroll
- [⏳] Apple Books iOS 18 Reader UI: top header with back button, page countdown, close 'X'
- [⏳] Chapter header with serif title & ornate divider
- [⏳] Bottom bar with page progress indicator and menu button
- [⏳] "Themes & Settings" bottom sheet matching reference:
  - Font size adjuster pill `[ A | A ]`
  - Layout toggle (Paginated vs Scroll)
  - Brightness slider
  - 6 Themes: Original, Quiet, Paper, Bold, Calm, Focus
  - Customize sub-sheet
- [⏳] Reading progress persistence & restoration
- [⏳] PDF reader with page rendering, pinch zoom, page jump

### Phase 5 — Online Sources & Novels
- [⏳] `NovelSource` implementation
- [⏳] Browse catalogue & Source search
- [⏳] Novel details view: cover, synopsis, tags, chapter list
- [⏳] Online chapter reader with normalized HTML rendering

### Phase 6 — Downloads & Library Prompt
- [⏳] Persistent download queue with state machine (queued, running, completed, paused, cancelled, failed)
- [⏳] Exact library membership prompt on chapter download:
  - "Add to Library? / Add '{novel title}' to your library to find it easily and check for new chapters. / Add to Library · Not Now"
  - Not Now session suppression
  - Downloads proceed regardless of choice
- [⏳] Chapter content & image caching for genuine offline reading

### Phase 7 — Reading Workflows & Polish
- [⏳] Continue Reading hero cards on Home
- [⏳] Reading history and unread chapter badges
- [⏳] Storage management & cache clearing
- [⏳] Backup and restore
