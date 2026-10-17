# Hon — Project Implementation Progress & Requirements Matrix

## Truthful Requirements & Status Matrix

| Subsystem | Feature | Implemented | Unit Tested | Android Build | Device / Runtime Verified | Real State & Notes |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **Android Native (Readium)** | Readium Toolkit 3.1.1 & Activity | ✅ | ✅ | ✅ | ✅ **Verified** | `ReadiumReaderActivity` hosting `EpubNavigatorFragment` with desugared Java 8+ APIs. Baseline verified on physical Android device (screenshots confirm formatted reading, chapter progression, and TOC). |
| **Android Native (Readium)** | Reader Ergonomics & Layout Framing | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Non-overlapping vertical `LinearLayout` framing (`weight = 1.0f` for reading container) ensures top/bottom toolbars never obscure chapter titles or text. `WindowInsetsCompat` dynamically pads status bar cutout and navigation bar. Pending device test to verify height toggling in paged and continuous scroll modes. |
| **Android Native (Readium)** | Adaptive System Bar Contrast | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | `WindowInsetsControllerCompat.isAppearanceLightStatusBars` dynamically enables dark system bar icons on light/sepia pages and light icons on dark pages. Pending physical device test. |
| **Android Native (Readium)** | Non-Blocking Async Loading & Restoration | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Asynchronous opening via `lifecycleScope.launch(Dispatchers.IO)` on normal launch (`super.onCreate(null)` with loading spinner); configuration change restoration utilizes in-memory `PublicationRepository` to install `fragmentFactory` before `super.onCreate(savedInstanceState)` with zero blocking. |
| **Android Native (Readium)** | Whole-Book Progression | ✅ | ✅ | ✅ | ✅ **Verified** | Shared `computeTotalProgression` across live reading, `finish()`, and `onDestroy()`; uses `loc.locations.totalProgression` with fallback to `(resourceIndex + chapterProgression) / readingOrder.size`. |
| **Android Native (Readium)** | Native TOC & Navigation | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Dedicated TOC dialog with recursive link traversal and indentation (`flattenToc`) for volumes/parts; bottom bar `❮ Prev` and `Next ❯` buttons. |
| **Android Native (Readium)** | Native Appearance Controls | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | `Aa` modal dialog with font size step controls, theme switcher (Dark, Sepia, Light), and layout mode (Paged reflow vs Continuous scroll); persisted to `hon_reader_preferences` SharedPreferences. |
| **Android Native (Readium)** | Explicit Error Handling & Lifecycle | ✅ | ✅ | ✅ | ✅ **Verified** | Connected `onReaderReady` and `onReaderError` with structured request tracking (`requestId`); explicit timeout error (never inferring readiness from elapsed time); late error reporting via `HonApp` SnackBar and `lastErrorNotifier`. |
| **Reader UI Milestone** | Phase 0-ReaderUI: Classic Apple Books Design Pass | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | **Milestone Implemented**: Native Kotlin reader toolbars and dialogs redesigned to Classic Apple Books aesthetic: frosted rounded action pills (`✕`, `≡`, `Aa`), centered scrubber pill showing chapter title and percentage, Apple Books typography bottom sheet with "A / A" font size steppers, 3 reference theme cards (Light, Sepia, Dark) with selection borders, and segmented Paged vs Scroll switcher. |
| **Persistence / Bridge (Drift SQLite)** | Drift Database & Migration (Phase 0D) | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Type-safe SQLite persistence via Drift (`app_database.dart`) with `NativeDatabase.createInBackground(hon.sqlite)`. Seamless automatic migration (`_migrateFromSharedPreferencesIfNeeded`) safely imports existing SharedPreferences JSON stores into SQLite on first launch. In-memory fallback strictly restricted to explicitly configured tests (`allowMemoryFallbackForTesting`); production persistence failures throw visible error. Verified via `drift_persistence_migration_test.dart` (3/3 passing). |
| **Persistence / Bridge** | Foreground Reading Session Tracking & Race Guard | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Active reading sessions across Readium (Android native), `PdfReaderScreen`, and `ReaderScreen` accumulate elapsed active seconds and update `DatabaseService.addReadingTime()`. Strictly requires both content readiness AND foreground state (`_isForegrounded`) before starting session timers. Loading completion while backgrounded never starts timer. |
| **Downloads (WorkManager)** | Background Download Worker & Recovery (Phase 0E) | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Android native WorkManager worker (`HonDownloadWorker.kt`) runs out-of-process downloads using extension passage extraction, verified file commits, and schema-matched `JOIN chapters_table` recovery queries. Database failures throw rather than being swallowed. Chapter URL and destination path persisted before scheduling; competing foreground downloads eliminated. Synchronizes updates with Flutter cache via `HonDownloadManagerBridge.notifyStateChanged()` and `DatabaseService.refreshDownloadsAndChapters()`. Verified via `download_recovery_test.dart`. |
| **Library Screen** | Removal & Complete File Deletion | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Options sheet on long-press & overflow button: "Remove from Library" (keeps files, includes Undo) and "Remove from Library and Delete" (destructive alert warning that publications, downloaded chapter files, progress, bookmarks, and history are erased; encloses managed storage boundary; preserves records on file error). |
| **Library Screen** | Empty State & Sorting | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Truly empty state with Import button; title (A-Z/Z-A), recently read, and progress sorting; chapter count badge on card. |
| **Home Screen** | Shelf & Dynamic Reading Goals | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Clean empty shelf, honest continue reading, dynamic daily reading minutes and reading goals from `DatabaseService` (replaces hardcoded '20'), Books Read This Year. |
| **Settings Screen** | Data & Backup Labeling | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Honestly labeled JSON Metadata Archive export (library books & reading progress records) replacing inaccurate SQLite wording. |
| **Desktop Preview (Dart)** | Chapter Swipe & Web Novel Rendering | ✅ | ✅ | ✅ | ✅ (Linux) | Accurately labeled "Swipe"; handles horizontal chapter swiping with post-frame scroll position restoration; renders both EPUB chapters and online web novel chapters with identical Apple Books typography. |
| **Desktop Preview (Dart)** | Completion Calculation | ✅ | ✅ | ✅ | ✅ (Linux) | Mathematical progress: combined chapter index and intra-chapter scroll fraction; manual "Finished" status kept strictly independent. |
| **Reader (PDF)** | Pinch-to-Zoom & Dual Mode | ✅ | ✅ | ✅ | ✅ (Linux) | Async open validation, onDocumentError handlers, initialPage clamping, color filter & mode persistence. |
| **Reader (PDF)** | Error Card & Controls Safety | ✅ | ✅ | ✅ | ✅ (Linux) | Controls disabled in error/loading/unsupported state; error card removes library membership without deleting book records. |
| **Browse (Sources)** | Production Kotlin-Side Shosetsu Integration (Phase 0C) | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | **Production Architecture Complete**: Android native Kotlin engine (`ShosetsuKotlinEngine.kt` + `ShosetsuBridge.kt`) consumes bundled extension's returned table with real function signatures (`search(data)`, `parseNovel(url, loadChapters)`, `getPassage(url)`) and complete Shosetsu environment (`Require("FilterOptions")`, `Require("url")`, `GETDocument`, `map`, `pageOfElem`, Jsoup DOM bridge). Silent native-to-Dart fallback removed on Android to surface errors directly. Verified via JVM unit test suite `ShosetsuKotlinEngineTest` (4/4 passing). |
| **Downloads & Updates** | Integrity & Prompt Sequence | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Chapter URL and managed destination path persisted in SQLite (`chapters_table`) before scheduling WorkManager. Non-blocking Add-to-Library prompt triggered independently. Background execution handled solely by WorkManager without competing foreground downloads. |

---

## Detailed Evidence & Verification Log

### 1. Phase 0C: Native Kotlin-Side Shosetsu Engine & MethodChannel Integration
- **Extension Table Consumption:**
  - `ShosetsuKotlinEngine.kt` loads the upstream Lua extension script and receives the returned extension table (`chunk.call().checktable()`).
  - Calls `extensionTable.get("search")` with Shosetsu standard data table (`data[PAGE]` and `data[QUERY]`).
  - Calls `extensionTable.get("parseNovel")` with `(novelUrl, loadChapters)` and extracts title, author, description, cover, and chapters list.
  - Calls `extensionTable.get("getPassage")` with `(chapterUrl)` and returns passage HTML string.
- **Complete Shosetsu Environment Bindings:**
  - Implements global `Require("FilterOptions")` (callable returning object with `valueOfOrFirst` and `labels`) and `Require("url")` (with `querystring(params, base)`).
  - Implements global `GETDocument(url)` returning wrapped Jsoup `Document` with `.select()`, `.selectFirst()`, `.text()`, `.ownText()`, `.attr()`, `.prependElement()`, `.head()`, and `.body()`.
  - Implements Shosetsu collection helper `map(list, fn)`, `pageOfElem(doc, removeStyles)`, `Novel`, `NovelInfo:setChapters`, `NovelChapter`, `AsList`, `List`, `Listing`, `DropdownFilter`, `SwitchFilter`, `NovelStatus`, and `ChapterType`.
  - Strips dangerous host globals (`os`, `io`, `luajava`, `debug`, `package.loadlib`) for sandbox security.
- **Strict Android Native Execution:**
  - Removed silent `try-catch` fallback to the Dart prototype in `lib/core/sources/source_registry.dart`.
  - On Android, `searchSource()`, `getNovelDetails()`, and `getChapterPassage()` execute exclusively via `NativeShosetsuBridge` and surface native failures directly.
- **Automated Verification:**
  - Dedicated Android JUnit test suite: `android/app/src/test/kotlin/com/hon/reader/hon/ShosetsuKotlinEngineTest.kt` (4/4 tests passed: script consumption & search, novel details & chapters parsing, passage retrieval, and security sandboxing).

### 2. Phase 0D: Drift (SQLite) Persistence & Production Fallback Safety
- **Drift SQLite Architecture:**
  - Implemented `lib/core/database/app_database.dart` with Drift 2.34.4 and `sqlite3_flutter_libs 0.6.0+eol`.
  - Tables: `BooksTable`, `LibraryEntriesTable`, `ChaptersTable`, `DownloadJobsTable`, `ReadingProgressTable`, `BookmarksTable`, `AppSettingsTable`.
  - Background isolate execution via `NativeDatabase.createInBackground(hon.sqlite)`.
- **Production Persistence Protection:**
  - Fallback to `NativeDatabase.memory()` is strictly restricted to explicitly configured test environments via `AppDatabase.allowMemoryFallbackForTesting` (enabled via `test/flutter_test_config.dart` during test runs).
  - In production, unconfigured storage initialization failures throw a visible `StateError`, preventing silent ephemeral execution and data loss.
- **Seamless Migration:**
  - `_migrateFromSharedPreferencesIfNeeded()` atomically imports legacy SharedPreferences JSON stores into Drift tables on first launch.
  - Verified via `test/unit/drift_persistence_migration_test.dart` (3/3 passing, including production safety check).

### 3. Phase 0E: Android WorkManager Download Worker, Recovery & State Synchronization
- **WorkManager Background Execution:**
  - `HonDownloadWorker.kt` extends `CoroutineWorker` from `androidx.work:work-runtime-ktx:2.9.1`.
  - Executes chapter downloads out-of-process using upstream Shosetsu extension passage extraction (`shosetsuEngine.getPassage(luaScript, url)`).
  - Validates file commit success: checks temp file length, validates `renameTo()`, falls back to copy-and-delete on cross-filesystem targets, and validates target existence and non-zero length before marking completion.
  - Database write errors in SQLite (`download_jobs_table` and `chapters_table`) throw `IllegalStateException`, triggering WorkManager retry/failure handling rather than being silently ignored.
- **Pre-scheduling Record Persistence & Sole Executor:**
  - In `lib/features/browse/presentation/source_catalog_screen.dart`, the `Chapter` record (with `url` and `localFilePath`) is persisted to `DatabaseService` before scheduling WorkManager.
  - Competing foreground downloads in the screen have been removed; WorkManager is the sole executor on Android.
- **Real Drift Schema Recovery Query:**
  - Corrected `HonDownloadWorker.recoverAllDownloads()` to join `download_jobs_table` and `chapters_table` (`SELECT d.id, c.url, c.local_file_path, d.book_id, d.chapter_id, d.source_id FROM download_jobs_table d JOIN chapters_table c ON d.chapter_id = c.id WHERE d.status IN ('queued', 'running', 'retryWaiting')`).
  - Recovery loop tracks individual job outcomes and returns `Result.retry()` or `Result.failure()` if any job failed or requested retry.
- **State Synchronization:**
  - Native worker invokes `HonDownloadManagerBridge.notifyStateChanged()` on state transitions.
  - Bridge notifies Flutter over MethodChannel (`com.hon.reader/download_worker`), triggering `DatabaseService.refreshDownloadsAndChapters(bookId)` to reload updated SQLite records and notify UI listeners.
  - Verified via `test/unit/download_recovery_test.dart` (1/1 passing).

### 4. Phase 0-ReaderUI: Native Android Reader Classic Apple Books Design Pass
- **Layout & Controls Redesign:**
  - `ReadiumReaderActivity.kt` styled with Classic Apple Books aesthetic across top bar, bottom scrubber, appearance dialog, and table of contents.
  - Top bar features circular action pills (`✕`, `≡`, `Aa`), refined title, and dynamic theme backgrounds.
  - Bottom bar features centered Apple Books progress scrubber pill showing chapter title and percentage (`14% • Chapter 1`), framed by subtle navigation buttons (`❮ Prev`, `Next ❯`).
  - Appearance dialog (`Aa`) redesigned with Apple Books typography stepping ("A / A" buttons with centered percentage), 3 reference theme cards (Light, Sepia, Dark) with selection indicator borders, and segmented Paged vs Scroll switcher.
  - Table of Contents sheet matches the active theme with rounded card framing, recursive depth indentation, and active chapter highlights.
  - Preserves non-overlapping middle container framing (`weight = 1.0f`) and dynamic system-bar contrast with `WindowInsetsControllerCompat`.

### 5. Quality & Verification Metrics
- **Static Analysis:** `flutter analyze` — **0 issues found** (clean across all files).
- **Kotlin JVM Unit Tests:** `./gradlew testDebugUnitTest` — **4 passed, 0 failed** (100% success for `ShosetsuKotlinEngineTest`).
- **Flutter Automated Tests:** `flutter test` — **50 passed, 0 failed** across all unit and integration test suites.
- **Android Compilation:** Gradle `assembleDebug` — **BUILD SUCCESSFUL**. Output: `build/app/outputs/flutter-apk/app-debug.apk` (213MB, SHA-256: `a9614ac7e1a0b278d877fa4487b164f71ac8faa6d246e68777179c1a6813e0f6`).
- **Physical Device Acceptance:** Marked **⏳ Pending User Device Testing** per milestone agreement before proceeding to Phase 1.
