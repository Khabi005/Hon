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
| **Persistence / Bridge** | Foreground Reading Session Tracking & Race Guard | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Active reading sessions across Readium (Android native), `PdfReaderScreen`, and `ReaderScreen` accumulate elapsed active seconds and update `DatabaseService.addReadingTime()`. Strictly requires both content readiness AND foreground state (`_isForegrounded`) before starting session timers. Loading completion while backgrounded never starts timer. |
| **Library Screen** | Removal & Complete File Deletion | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Options sheet on long-press & overflow button: "Remove from Library" (keeps files, includes Undo) and "Remove from Library and Delete" (destructive alert warning that publications, downloaded chapter files, progress, bookmarks, and history are erased; encloses managed storage boundary; preserves records on file error). |
| **Library Screen** | Empty State & Sorting | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Truly empty state with Import button; title (A-Z/Z-A), recently read, and progress sorting; chapter count badge on card. |
| **Home Screen** | Shelf & Dynamic Reading Goals | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Clean empty shelf, honest continue reading, dynamic daily reading minutes and reading goals from `DatabaseService` (replaces hardcoded '20'), Books Read This Year. |
| **Settings Screen** | Data & Backup Labeling | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Honestly labeled JSON Metadata Archive export (library books & reading progress records) replacing inaccurate SQLite wording. |
| **Desktop Preview (Dart)** | Chapter Swipe & Web Novel Rendering | ✅ | ✅ | ✅ | ✅ (Linux) | Accurately labeled "Swipe"; handles horizontal chapter swiping with post-frame scroll position restoration; renders both EPUB chapters and online web novel chapters with identical Apple Books typography. |
| **Desktop Preview (Dart)** | Completion Calculation | ✅ | ✅ | ✅ | ✅ (Linux) | Mathematical progress: combined chapter index and intra-chapter scroll fraction; manual "Finished" status kept strictly independent. |
| **Reader (PDF)** | Pinch-to-Zoom & Dual Mode | ✅ | ✅ | ✅ | ✅ (Linux) | Async open validation, onDocumentError handlers, initialPage clamping, color filter & mode persistence. |
| **Reader (PDF)** | Error Card & Controls Safety | ✅ | ✅ | ✅ | ✅ (Linux) | Controls disabled in error/loading/unsupported state; error card removes library membership without deleting book records. |
| **Browse (Sources)** | Upstream Shosetsu Lua Extension Engine (Phase 0C) | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Bounded upstream proof complete with real upstream extension (`assets/sources/gutenberg.lua`). Completes search → novel details → chapter list → readable chapter content. Real DOM parsing & pure Dart Lua 5.3 interpreter (`lua_dardo_plus`). Honest network error cards; zero synthetic or mock fallbacks. |
| **Downloads & Updates** | Integrity & Prompt Sequence | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Chapter downloads save real passage content into managed storage (`StorageService.instance.chaptersDir`); Add-to-Library prompt queues downloads durably before prompting. |

---

## Detailed Evidence & Verification Log

### 1. Phase 0C: Upstream Shosetsu Lua Extension Engine Proof of Functionality
- **Upstream Source Extension Used:** Project Gutenberg (`assets/sources/gutenberg.lua`, matching upstream Shosetsu repository specification).
- **Architecture:** Pure Dart Lua 5.3 runtime (`lua_dardo_plus`) with Shosetsu Kotlin-lib environment bridge (`Document`, `Element`, `Elements`, CSS selectors, attribute extraction, `Novel`, `NovelInfo`, `NovelChapter`, `NovelStatus`, `Require("FilterOptions")`, `Require("url")`, `map`, `AsList`, `pageOfElem`).
- **Complete Pipeline Verified End-to-End:**
  1. **Search:** Executes live search query (e.g. `"pride"`) against source. Parses HTML search results into structured `SourceNovelSummary` items with title, link, and cover thumbnail.
  2. **Novel Details:** Invokes `parseNovel("/ebooks/1342", true)` to extract publication metadata, author (*Jane Austen*), synopsis, genres, and the complete chapter list.
  3. **Chapter List:** Accurately parses chapter title, release date, and online passage link (`/cache/epub/1342/pg1342-images.html`).
  4. **Readable Chapter Passage:** Invokes `getPassage(url)` to retrieve the complete HTML text of the novel. Seamlessly renders in Hon's reader screen using Apple Books typography, theme settings, font sizing, and reading time accumulation.
  5. **Honest Error Handling:** If connection drops or HTTP errors occur (e.g. SocketException, 404, 500), `SourceNetworkException` is thrown and displayed via an honest error banner with a "Retry" button. Zero synthetic or mock fallbacks.
  6. **Automated Test Suite:** Verified via `test/unit/shosetsu_lua_engine_test.dart` (6 passed tests verifying live and fixture parsing, DOM extraction, chapter list integrity, and network error handling).

### 2. Foreground Reading Session Tracking & Race Condition Guard
- **Lifecycle Guard:** Tracked `_isForegrounded` state across `ReadiumReaderService` (native Android), `PdfReaderScreen`, and `ReaderScreen` (Dart reader).
- **Background Loading Race Fixed:** If a user backgrounds the app while an EPUB or PDF is still loading/parsing, the session timer does NOT start upon loading completion. The timer starts strictly when **both content readiness AND foreground state** are verified.
- **Unit Test Verification:** Added unit test `Loading completion while backgrounded (isForegrounded: false) does NOT start session timer` in `test/unit/readium_reader_service_test.dart`, confirming timer remains `null` until resume.

### 3. Managed Storage Boundaries & File Deletion Integrity
- **Path Containment Clarification:** Updated `isPathInsideManagedStorage(filePath)` documentation to clarify that it normalizes path strings via `path.canonicalize()` (resolving `.` and `..` segments) and tests prefix containment without filesystem-level symlink resolution.
- **Complete File Deletion:** `DatabaseService.deleteBook()` aggregates publication file, cover image, and all downloaded chapter files (`ch.localFilePath`). External user files outside managed storage are protected and never deleted from disk. Failed file deletions preserve database records for retry.

### 4. Layout Framing & Adaptive Contrast (Pending Consolidated On-Device Test)
- **Layout Framing:** Vertical `LinearLayout` framing (`weight = 1.0f`) places reading container strictly between top and bottom toolbars without overlap.
- **Adaptive Contrast:** System bar icons dynamically toggle between dark (for light/sepia pages) and light (for dark pages) using `WindowInsetsControllerCompat`.
- **Status:** Labeled `⏳ Pending Next APK Test` until consolidated physical on-device test is run.

### 5. Quality & Verification Metrics
- **Static Analysis:** `flutter analyze` — **0 issues found** (clean).
- **Automated Tests:** `flutter test` — **39 passed, 0 failed** across all unit and widget tests.
- **Android Compilation:** `./gradlew assembleDebug` — **BUILD SUCCESSFUL in 17s** (`build/app/outputs/apk/debug/app-debug.apk` built).
