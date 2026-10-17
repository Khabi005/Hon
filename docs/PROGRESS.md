# Hon — Project Implementation Progress & Requirements Matrix

## Truthful Requirements & Status Matrix

| Subsystem | Feature | Implemented | Unit Tested | Android Build | Device / Runtime Verified | Real State & Notes |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **Android Native (Readium)** | Readium Toolkit 3.1.1 & Activity | ✅ | ✅ | ✅ | ✅ **Verified** | `ReadiumReaderActivity` hosting `EpubNavigatorFragment` with desugared Java 8+ APIs. Baseline verified on physical Android device (screenshots confirm formatted reading, chapter progression, and TOC). |
| **Android Native (Readium)** | Reader Ergonomics & Layout Framing | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Non-overlapping vertical `LinearLayout` framing (`weight = 1.0f` for reading container) ensures top/bottom toolbars never obscure chapter titles or text. `WindowInsetsCompat` dynamically pads status bar cutout and navigation bar. Pending device test to verify height toggling in paged and continuous scroll modes. |
| **Android Native (Readium)** | Adaptive System Bar Contrast | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | `WindowInsetsControllerCompat.isAppearanceLightStatusBars` dynamically enables dark system bar icons on light/sepia pages and light icons on dark pages. Pending physical device test. |
| **Android Native (Readium)** | Non-Blocking Async Loading & Restoration | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Asynchronous opening via `lifecycleScope.launch(Dispatchers.IO)` on normal launch (`super.onCreate(null)` with loading spinner); configuration change restoration utilizes in-memory `PublicationRepository` to install `fragmentFactory` before `super.onCreate(savedInstanceState)` with zero blocking. |
| **Android Native (Readium)** | Whole-Book Progression | ✅ | ✅ | ✅ | ✅ **Verified** | Shared `computeTotalProgression` across live reading, `finish()`, and `onDestroy()`; uses `loc.locations.totalProgression` with fallback to `(resourceIndex + chapterProgression) / readingOrder.size`. |
| **Android Native (Readium)** | Native TOC & Navigation | ✅ | ✅ | ✅ | ✅ **Verified** | Dedicated TOC dialog with recursive link traversal and indentation (`flattenToc`) for volumes/parts; bottom bar `❮ Prev` and `Next ❯` buttons. |
| **Android Native (Readium)** | Native Appearance Controls | ✅ | ✅ | ✅ | ✅ **Verified** | `Aa` modal dialog with font size step controls, theme switcher (Dark, Sepia, Light), and layout mode (Paged reflow vs Continuous scroll); persisted to `hon_reader_preferences` SharedPreferences. |
| **Android Native (Readium)** | Explicit Error Handling & Lifecycle | ✅ | ✅ | ✅ | ✅ **Verified** | Connected `onReaderReady` and `onReaderError` with structured request tracking (`requestId`); explicit timeout error (never inferring readiness from elapsed time); late error reporting via `HonApp` SnackBar and `lastErrorNotifier`. |
| **Reader UI Milestone** | Phase 0-ReaderUI: Classic Apple Books Design Pass | 📋 | — | — | — | **Explicitly scheduled dedicated milestone**: Native Kotlin reader toolbars and dialogs redesigned to Classic Apple Books aesthetic (clean bottom toolbar, classic typography sheets, subtle TOC / bookmark ribbon) combined with modern Apple Books paragraph formatting & themes (from user screenshots). Kept strictly separate from Flutter widgets. |
| **Persistence / Bridge** | Multi-Book Bounded Write Queue | ✅ | ✅ | ✅ | ✅ (Device/Linux) | `_pendingByBook` isolation; `onPause()` dispatches `onReaderPaused` for immediate disk flush; `onReaderClosed` with null/empty locator preserves existing progress untouched (no 0% reset); persisted to SharedPreferences JSON collections (SQLite Drift is Phase 0D target). |
| **Persistence / Bridge** | Reading Session Duration Tracking | ✅ | ✅ | ✅ | ✅ (Linux) | Foreground reader sessions across Readium (Android native), `PdfReaderScreen`, and `ReaderScreen` accumulate active elapsed seconds and continuously update `DatabaseService.addReadingTime()`. |
| **Library Screen** | Removal & Deletion Actions | ✅ | ✅ | ✅ | ✅ (Linux) | Dedicated options sheet on card long-press & overflow button with exact actions: "Remove from Library" (keeps downloaded files) and "Remove from Library and Delete" (destructive confirmation alert; removes entry, purges DB, and deletes local files from disk). |
| **Library Screen** | Empty State & Sorting | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Truly empty state with Import button; title (A-Z/Z-A), recently read, and progress sorting; chapter count badge on card. |
| **Home Screen** | Shelf & Dynamic Reading Goals | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Clean empty shelf, honest continue reading, dynamic daily reading minutes and reading goals from `DatabaseService` (replaces hardcoded '20'), Books Read This Year. |
| **Settings Screen** | Data & Backup Labeling | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Honestly labeled JSON Metadata Archive export (library books & reading progress records) replacing inaccurate SQLite wording. |
| **Desktop Preview (Dart)** | Chapter Swipe Mode | ✅ | ✅ | ✅ | ✅ (Linux) | Accurately labeled "Swipe"; handles horizontal chapter swiping with post-frame scroll position restoration. |
| **Desktop Preview (Dart)** | Completion Calculation | ✅ | ✅ | ✅ | ✅ (Linux) | Mathematical progress: combined chapter index and intra-chapter scroll fraction; manual "Finished" status kept strictly independent. |
| **Reader (PDF)** | Pinch-to-Zoom & Dual Mode | ✅ | ✅ | ✅ | ✅ (Linux) | Async open validation, onDocumentError handlers, initialPage clamping, color filter & mode persistence. |
| **Reader (PDF)** | Error Card & Controls Safety | ✅ | ✅ | ✅ | ✅ (Linux) | Controls disabled in error/loading/unsupported state; error card removes library membership without deleting book records. |
| **Browse (Sources)** | Catalogue Integrity | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Mock catalogues disabled (`enableDemoCatalogues = false`); clean empty state until live Lua sources in Phase 0C. |
| **Downloads & Updates** | Integrity & Prompt Sequence | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Synthetic updates removed; Section 5 Add-to-Library prompt queues downloads durably before prompting. |
| **Phase 0C Target** | Upstream Shosetsu Lua Engine | 📋 | — | — | — | **Bounded proof of functionality**: One real upstream extension → search → novel details → chapter list → readable chapter, followed by compatibility and sandboxing. |

---

## Detailed Evidence & Verification Log

### 1. Device Smoke Test Milestone
- **On-Device Baseline Verification:** Confirmed on physical Android hardware via user smoke test. Readium rendering operates natively without fallback; TOC populated and navigated; appearance dialog switches themes and font sizes; locator callbacks persist progression to SharedPreferences JSON storage (SQLite Drift target scheduled for Phase 0D).
- **EPUB Paragraph Spacing Investigation:**
  - Evaluated two EPUBs: *Lord of the Mysteries Vol 1* (`lotm.epub`) and *Pride and Prejudice* (`pride_and_prejudice.epub`).
  - *LotM* CSS inspection: contains `margin: 0 0 30pt;` and `text-align: justify;` causing wide paragraph gaps and justified spacing.
  - *Pride and Prejudice* CSS inspection: contains `margin-top: 0; margin-bottom: 0; padding: 1em; text-align: justify;`.
  - Conclusion: Spacing variations stem directly from publisher-authored CSS. Readium respects publisher CSS by default. Publisher styles are preserved to respect headings, italics, and deliberate publisher formatting.

### 2. Ergonomics & Contrast Fixes (Pending Device Retest)
- **Layout Framing:** Replaced overlapping `FrameLayout` in `ReadiumReaderActivity` with vertical `LinearLayout`. The reading container has `weight = 1.0f`, framed cleanly between the top bar and bottom bar when controls are visible, and expanding to full screen when controls are dismissed (`View.GONE`).
- **Device Retest Checkpoint:** Marked pending verification on next APK test to verify that toolbar toggling and container height changes do not unexpectedly shift reading positions in paged and continuous scroll modes.
- **Window Insets:** Added `ViewCompat.setOnApplyWindowInsetsListener` to dynamically offset top bar by status bar cutout and bottom bar by navigation bar inset.
- **Adaptive System Bar Contrast:** Added `updateSystemBars()` using `WindowInsetsControllerCompat.isAppearanceLightStatusBars`. Sets dark status-bar and navigation-bar icons for light and sepia modes, and light icons for dark mode. Marked pending verification on next APK test.

### 3. Library Actions & Foreground Reading Tracking
- **Library Removal Actions:** Added options sheet on long-press and overflow icon button on every library card and list row:
  - "Remove from Library": Removes library membership (`isInLibrary = false`), preserving local book entity, reading progress, and downloaded files on disk. Includes Undo snackbar.
  - "Remove from Library and Delete": Destructive confirmation dialog permanently deletes the local EPUB/PDF file and local cover from disk, purges database entries, and cleans up associated download jobs.
- **Reading Minutes Foreground Tracking:** Connected foreground reader session tracking in `ReadiumReaderService` (native Android EPUB), `PdfReaderScreen`, and `ReaderScreen` (Dart reader). Accumulates elapsed active seconds on pause/close/dispose and increments `DatabaseService.addReadingTime()`.

### 4. Host Verification & Build Quality
- **Static Analysis:** `flutter analyze` — **0 issues found**.
- **Automated Tests:** `flutter test` — **29 passed, 0 failed** (including unit tests for removal actions, file deletion, and reading time accumulation).
- **Android Compilation:** `./gradlew assembleDebug` — **BUILD SUCCESSFUL**.
