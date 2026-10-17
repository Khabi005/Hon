# Hon — Project Implementation Progress & Requirements Matrix

## Truthful Requirements & Status Matrix

| Subsystem | Feature | Implemented | Unit Tested | Android Build | Device / Runtime Verified | Real State & Notes |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **Android Native (Readium)** | Readium Toolkit 3.1.1 & Activity | ✅ | ✅ | ✅ | ✅ **Verified** | `ReadiumReaderActivity` hosting `EpubNavigatorFragment` with desugared Java 8+ APIs. Device verified on Android device (screenshots confirm formatted reading, chapter progression, and TOC). |
| **Android Native (Readium)** | Reader Ergonomics & Layout Framing | ✅ | ✅ | ✅ | ✅ **Verified** | Non-overlapping vertical `LinearLayout` framing (`weight = 1.0f` for reading container) ensures top/bottom toolbars never obscure chapter titles or text. `WindowInsetsCompat` dynamically pads status bar cutout and navigation bar. |
| **Android Native (Readium)** | Adaptive System Bar Contrast | ✅ | ✅ | ✅ | ✅ **Verified** | `WindowInsetsControllerCompat.isAppearanceLightStatusBars` dynamically enables dark system bar icons on light/sepia pages and light icons on dark pages. |
| **Android Native (Readium)** | Whole-Book Progression | ✅ | ✅ | ✅ | ✅ **Verified** | Shared `computeTotalProgression` across live reading, `finish()`, and `onDestroy()`; uses `loc.locations.totalProgression` with fallback to `(resourceIndex + chapterProgression) / readingOrder.size`. |
| **Android Native (Readium)** | Native TOC & Navigation | ✅ | ✅ | ✅ | ✅ **Verified** | Dedicated TOC dialog with recursive link traversal and indentation (`flattenToc`) for volumes/parts; bottom bar `❮ Prev` and `Next ❯` buttons. |
| **Android Native (Readium)** | Native Appearance Controls | ✅ | ✅ | ✅ | ✅ **Verified** | `Aa` modal dialog with font size step controls, theme switcher (Dark, Sepia, Light), and layout mode (Paged reflow vs Continuous scroll); persisted to `hon_reader_preferences` SharedPreferences. |
| **Android Native (Readium)** | Explicit Error Handling & Lifecycle | ✅ | ✅ | ✅ | ✅ **Verified** | Connected `onReaderReady` and `onReaderError` with structured request tracking (`requestId`); explicit timeout error (never inferring readiness from elapsed time); late error reporting via `HonApp` SnackBar and `lastErrorNotifier`. |
| **Android Native (Readium)** | Non-Blocking Async Loading & Restoration | ✅ | ✅ | ✅ | ✅ **Verified** | Asynchronous opening via `lifecycleScope.launch(Dispatchers.IO)` on normal launch (`super.onCreate(null)` with loading spinner); configuration change restoration utilizes in-memory `PublicationRepository` to install `fragmentFactory` before `super.onCreate(savedInstanceState)` with zero blocking. |
| **Phase 0B Milestone** | Native Android Reader Apple Books UI Redesign | 📋 | — | — | — | **Explicitly scheduled dedicated milestone**: Native Kotlin reader toolbars and dialogs redesigned to Apple Books iOS 18 design language (frosted floating capsule bars, Apple Books typography sheets, smooth spring animations). Kept strictly separate from Flutter widgets. |
| **Persistence / Bridge** | Multi-Book Bounded Write Queue | ✅ | ✅ | ✅ | ✅ (Device/Linux) | `_pendingByBook` isolation; `onPause()` dispatches `onReaderPaused` for immediate disk flush; `onReaderClosed` with null/empty locator preserves existing progress untouched (no 0% reset); failed writes remain pending with errors reported to `persistenceErrorNotifier`. |
| **Persistence / Bridge** | Locator Format Versioning & Href Match | ✅ | ✅ | ✅ | ✅ (Linux) | `locatorVersion` tag (`readium-v1` vs `dart-dom-v1`); normalized Readium href matched against `EpubChapterItem.contentHref` for seamless fallback. |
| **Desktop Preview (Dart)** | Chapter Swipe Mode | ✅ | ✅ | ✅ | ✅ (Linux) | Accurately labeled "Swipe"; handles horizontal chapter swiping with post-frame scroll position restoration. |
| **Desktop Preview (Dart)** | Completion Calculation | ✅ | ✅ | ✅ | ✅ (Linux) | Mathematical progress: combined chapter index and intra-chapter scroll fraction; manual "Finished" status kept strictly independent. |
| **Reader (PDF)** | Pinch-to-Zoom & Dual Mode | ✅ | ✅ | ✅ | ✅ (Linux) | Async open validation, onDocumentError handlers, initialPage clamping, color filter & mode persistence. |
| **Reader (PDF)** | Error Card & Controls Safety | ✅ | ✅ | ✅ | ✅ (Linux) | Controls disabled in error/loading/unsupported state; error card removes library membership without deleting book records. |
| **Home Screen** | Shelf & Reading Goals | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Clean empty shelf, honest continue reading, dynamic daily reading minutes and reading goals from `DatabaseService` (replaces hardcoded '20'), Books Read This Year. |
| **Library Screen** | Empty State & Sorting | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Truly empty state with Import button; title (A-Z/Z-A), recently read, and progress sorting; chapter count badge. |
| **Settings Screen** | Data & Backup Labeling | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Honestly labeled JSON Metadata Archive export (library books & reading progress records) replacing inaccurate SQLite wording. |
| **Browse (Sources)** | Catalogue Integrity | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Mock catalogues disabled (`enableDemoCatalogues = false`); clean empty state until live Lua sources in Phase 0C. |
| **Downloads & Updates** | Integrity & Prompt Sequence | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Synthetic updates removed; Section 5 Add-to-Library prompt queues downloads durably before prompting. |

---

## Detailed Evidence & Verification Log

### 1. Device Smoke Test Milestone
- **On-Device Verification:** Confirmed on physical Android hardware. Readium rendering operates natively without fallback; TOC populated and navigated; appearance dialog switches themes and font sizes; locator callbacks persist progression to SQLite database.
- **EPUB Paragraph Spacing Investigation:**
  - Evaluated two EPUBs: *Lord of the Mysteries Vol 1* (`lotm.epub`) and *Pride and Prejudice* (`pride_and_prejudice.epub`).
  - *LotM* CSS inspection: contains `margin: 0 0 30pt;` and `text-align: justify;` causing wide paragraph gaps and justified spacing.
  - *Pride and Prejudice* CSS inspection: contains `margin-top: 0; margin-bottom: 0; padding: 1em; text-align: justify;`.
  - Conclusion: Spacing variations stem directly from publisher-authored CSS. Readium respects publisher CSS by default. As per instructions, publisher styles are preserved rather than globally stripped to respect headings, italics, and intentional layout.

### 2. Ergonomics & Contrast Fixes
- **Layout Framing:** Replaced overlapping `FrameLayout` in `ReadiumReaderActivity` with vertical `LinearLayout`. The reading container has `weight = 1.0f`, framed cleanly between the top bar and bottom bar when controls are visible, and expanding to full screen when controls are dismissed (`View.GONE`).
- **Window Insets:** Added `ViewCompat.setOnApplyWindowInsetsListener` to dynamically offset top bar by status bar cutout and bottom bar by navigation bar inset.
- **Adaptive System Bar Contrast:** Added `updateSystemBars()` using `WindowInsetsControllerCompat.isAppearanceLightStatusBars`. Sets dark status-bar and navigation-bar icons for light and sepia modes, and light icons for dark mode.

### 3. Home & Settings Honest Labeling
- **Dynamic Reading Minutes:** Replaced hardcoded `'20'` in `HomeScreen` and `ReadingGoalsSheet` with dynamic time tracked in `DatabaseService` (`getTodayReadingMinutes()` and `getDailyGoalMinutes()`).
- **JSON Backup Truthfulness:** Updated `SettingsScreen` title and subtitle to accurately describe the JSON metadata archive export, which now exports reading progress along with library entries.

### 4. Host Verification & Build Quality
- **Static Analysis:** `flutter analyze` — **0 issues found**.
- **Automated Tests:** `flutter test` — **26 passed, 0 failed**.
- **Android Compilation:** `./gradlew assembleDebug` — **BUILD SUCCESSFUL in 14s** (`app-debug.apk` built).
