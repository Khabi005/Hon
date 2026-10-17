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
| **Browse (Sources)** | Upstream Shosetsu Lua Engine Prototype (Phase 0C) | ⚠️ Prototype Implemented | ✅ | ✅ | ⏳ **Pending Next APK Test** | **Experimental compatibility prototype**: pure-Dart Lua host (`lua_dardo_plus`) with DOM bridge, sandboxing, and worker isolate offloading. Executes upstream Project Gutenberg extension (`assets/sources/gutenberg.lua`, commit `e1dc0ee`). Stack argument passing eliminates injection. Off-UI-thread execution with 15s per-attempt budget and 45s total operation deadline. Stable source-qualified IDs (`$sourceId:${novel.id}`). Downloads durably enqueued BEFORE library prompt. External extensions gated until Kotlin runtime. Kotlin-side Shosetsu runtime remains production target. |
| **Downloads & Updates** | Integrity & Prompt Sequence | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Chapter downloads durably enqueued first (`DatabaseService.enqueueDownload`), independent of non-blocking Add-to-Library prompt response; saved to managed storage (`StorageService.instance.chaptersDir`). Durable background worker execution tracked under planned WorkManager phase. |

---

## Detailed Evidence & Verification Log

### 1. Phase 0C: Upstream Shosetsu Lua Extension Engine Compatibility Prototype
- **Architectural Positioning:**
  - This pure-Dart Lua execution layer (`lua_dardo_plus` + DOM bridge) is an **experimental compatibility prototype** developed to validate the Flutter browse/reader pipeline.
  - It is **NOT** an approved production replacement for the agreed Android Kotlin-side Shosetsu integration (`kotlin-lib` native host). Production architecture continues to target the Android Kotlin runtime.
  - The fetch-and-replay loop is an asynchronous cache-and-replay mechanism designed for stateless functional scrapers (such as Project Gutenberg); it does not provide general coroutine or multi-threaded runtime compatibility for arbitrary stateful extensions.
- **Upstream Source Extension Used & Provenance:**
  - Project Gutenberg extension (`assets/sources/gutenberg.lua`).
  - Upstream Repository: `https://github.com/wasu-code/novel-extensions` (`src/en/gutenberg.lua`).
  - Pinned Branch/Commit: `dev` (`e1dc0ee`).
  - Modifications: None (executed verbatim by the runtime compatibility bridge).
  - Repomix packaging: Embedded in `hon_review.xml` under `<file path="assets/sources/gutenberg.lua">` with complete upstream provenance header.
- **Execution Off UI Thread, Resource Cleanup & Two-Tier Deadline Budget:**
  - All Lua parsing, bytecode execution, and DOM manipulation run off the UI thread inside dedicated worker isolates via `Isolate.spawn`.
  - Placeholder `ReceivePort().sendPort` removed to prevent unclosed port resource leaks; `receivePort` is dynamically created per worker invocation and strictly closed inside `finally`.
  - Two-tier timeout architecture:
    - **Total Operation Deadline:** 45 seconds total across the entire replay cycle (tracked via `Stopwatch`).
    - **Per-Attempt Worker Budget:** 15 seconds per isolate execution. Outgoing HTTP timeouts dynamically bound to the remaining total budget.
    - If a worker exceeds its per-attempt budget, the isolate is terminated immediately via `isolate.kill(priority: Isolate.immediate)` and throws `SourceExecutionTimeoutException`.
- **Stack Argument Passing & Host Sandboxing:**
  - Replaced all string interpolation in `loadString()` with native Lua C-API stack operations (`ls.pushString()`, `ls.pushInteger()`, `ls.pushBoolean()`, `ls.setTable()`, `ls.call()`), preventing script injection or quote-escaping failures.
  - Dangerous host OS and IO libraries (`os.execute`, `os.remove`, `os.rename`, `io`, etc.) are stripped and set to `nil`. Only whitelisted DOM and Shosetsu globals are accessible.
- **Novel/Chapter Identity & Enqueue-Before-Prompt Sequence:**
  - Stable source-qualified identities: novel ID is `"$sourceId:${novel.id}"` (e.g. `'gutenberg:/ebooks/1342'`); chapter ID is `"$bookId:${chapter.id}"`.
  - Real machine source ID (`widget.sourceId`, e.g. `'gutenberg'`) is stored in `Book.sourceId` (never display name).
  - **Enqueue-Before-Prompt Sequence:** In `SourceCatalogScreen._handleDownloadChapters()`, `DatabaseService.instance.enqueueDownload(job)` (`status: DownloadStatus.queued`) and chapter record saving occur *first*. `AddToLibraryPrompt.checkAndPrompt()` is dispatched asynchronously without blocking the download pipeline, guaranteeing downloads proceed independently of whether the user accepts, declines, or dismisses the prompt.
  - Full background execution is tracked under the planned WorkManager worker phase.
- **Gated External Extension Installation:**
  - In `SourceRegistry.installExtension()`, extension installation is restricted to verified bundled sources (`'gutenberg'`). Third-party external installations are gated with a typed `SourceParseException` until the production Kotlin-side host runtime is verified.
- **Separated Test Suites & Live Test Semantics:**
  - **Unit Tests (`test/unit/shosetsu_lua_engine_test.dart`):** 10 fixture/mock-based unit tests verifying search, novel details, chapter parsing, E2E pipeline, socket failure, HTTP 500 error, stack argument passing with injection payloads, infinite loop timeout enforcement, host sandboxing neutralization, and source-qualified ID + durable download queue.
  - **Live Network Integration Tests (`test/integration/live_upstream_gutenberg_test.dart`):** Honest live test assertions against `www.gutenberg.org`. Offline runs use `markTestSkipped()` (no clean-return or silent passes); online runs strictly assert without catching/swallowing `SourceNetworkException`. Tests verify live catalog search for "pride", novel details for `/ebooks/1342`, and passage retrieval for Chapter 1.
  - **Physical Device Runtime:** Explicitly labeled `⏳ Pending Next APK Test` (consolidated at end of Phase 0).

### 2. Foreground Reading Session Tracking & Race Condition Guard
- **Lifecycle Guard:** Tracked `_isForegrounded` state across `ReadiumReaderService` (native Android), `PdfReaderScreen`, and `ReaderScreen` (Dart reader).
- **Background Loading Race Fixed:** If a user backgrounds the app while an EPUB or PDF is still loading/parsing, the session timer does NOT start upon loading completion. The timer starts strictly when **both content readiness AND foreground state** are verified.
- **Unit Test Verification:** Verified via `test/unit/readium_reader_service_test.dart`.

### 3. Managed Storage Boundaries & File Deletion Integrity
- **Path Containment Clarification:** Updated `isPathInsideManagedStorage(filePath)` documentation to clarify that it normalizes path strings via `path.canonicalize()` (resolving `.` and `..` segments) and tests prefix containment without filesystem-level symlink resolution.
- **Complete File Deletion:** `DatabaseService.deleteBook()` aggregates publication file, cover image, and all downloaded chapter files (`ch.localFilePath`). External user files outside managed storage are protected and never deleted from disk. Failed file deletions preserve database records for retry.

### 4. Layout Framing & Adaptive Contrast (Pending Consolidated On-Device Test)
- **Layout Framing:** Vertical `LinearLayout` framing (`weight = 1.0f`) places reading container strictly between top and bottom toolbars without overlap.
- **Adaptive Contrast:** System bar icons dynamically toggle between dark (for light/sepia pages) and light (for dark pages) using `WindowInsetsControllerCompat`.
- **Status:** Labeled `⏳ Pending Next APK Test` until consolidated physical on-device test is run.

### 5. Quality & Verification Metrics
- **Static Analysis:** `flutter analyze` — **0 issues found** (clean).
- **Automated Tests:** `flutter test` — **46 passed, 0 failed** across all unit and integration test suites.
- **Android Compilation:** `./gradlew assembleDebug` — **BUILD SUCCESSFUL**.
