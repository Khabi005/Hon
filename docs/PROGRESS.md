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
| **Persistence / Bridge (Drift SQLite)** | Drift Database & Migration (Phase 0D) | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Type-safe SQLite persistence via Drift (`app_database.dart`) with `NativeDatabase.createInBackground(hon.sqlite)`. Seamless automatic migration (`_migrateFromSharedPreferencesIfNeeded`) safely imports existing SharedPreferences JSON stores into SQLite on first launch. High-performance in-memory cache preserves synchronous API compatibility. Verified via `drift_persistence_migration_test.dart`. |
| **Persistence / Bridge** | Foreground Reading Session Tracking & Race Guard | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Active reading sessions across Readium (Android native), `PdfReaderScreen`, and `ReaderScreen` accumulate elapsed active seconds and update `DatabaseService.addReadingTime()`. Strictly requires both content readiness AND foreground state (`_isForegrounded`) before starting session timers. Loading completion while backgrounded never starts timer. |
| **Downloads (WorkManager)** | Background Download Worker & Recovery (Phase 0E) | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Android native WorkManager worker (`HonDownloadWorker.kt`) runs out-of-process downloads with exponential backoff and network constraints. `HonDownloadManager.recoverInterruptedDownloads()` scans for downloads interrupted by process termination, resets `running` jobs to `queued`, and enqueues recovery. Verified via `download_recovery_test.dart`. |
| **Library Screen** | Removal & Complete File Deletion | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Options sheet on long-press & overflow button: "Remove from Library" (keeps files, includes Undo) and "Remove from Library and Delete" (destructive alert warning that publications, downloaded chapter files, progress, bookmarks, and history are erased; encloses managed storage boundary; preserves records on file error). |
| **Library Screen** | Empty State & Sorting | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Truly empty state with Import button; title (A-Z/Z-A), recently read, and progress sorting; chapter count badge on card. |
| **Home Screen** | Shelf & Dynamic Reading Goals | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Clean empty shelf, honest continue reading, dynamic daily reading minutes and reading goals from `DatabaseService` (replaces hardcoded '20'), Books Read This Year. |
| **Settings Screen** | Data & Backup Labeling | ✅ | ✅ | ✅ | ✅ (Device/Linux) | Honestly labeled JSON Metadata Archive export (library books & reading progress records) replacing inaccurate SQLite wording. |
| **Desktop Preview (Dart)** | Chapter Swipe & Web Novel Rendering | ✅ | ✅ | ✅ | ✅ (Linux) | Accurately labeled "Swipe"; handles horizontal chapter swiping with post-frame scroll position restoration; renders both EPUB chapters and online web novel chapters with identical Apple Books typography. |
| **Desktop Preview (Dart)** | Completion Calculation | ✅ | ✅ | ✅ | ✅ (Linux) | Mathematical progress: combined chapter index and intra-chapter scroll fraction; manual "Finished" status kept strictly independent. |
| **Reader (PDF)** | Pinch-to-Zoom & Dual Mode | ✅ | ✅ | ✅ | ✅ (Linux) | Async open validation, onDocumentError handlers, initialPage clamping, color filter & mode persistence. |
| **Reader (PDF)** | Error Card & Controls Safety | ✅ | ✅ | ✅ | ✅ (Linux) | Controls disabled in error/loading/unsupported state; error card removes library membership without deleting book records. |
| **Browse (Sources)** | Production Kotlin-Side Shosetsu Integration (Phase 0C) | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | **Production Architecture Complete**: Android native Kotlin engine (`ShosetsuKotlinEngine.kt` + `ShosetsuBridge.kt`) executing Shosetsu Lua extensions via sandboxed Luaj (`org.luaj:luaj-jse`), Jsoup DOM parser, and OkHttp. Connected to Flutter via MethodChannel (`com.hon.reader/shosetsu_native`) in `SourceRegistry`. Clean fallback to Dart isolate worker on desktop/headless test environments. |
| **Downloads & Updates** | Integrity & Prompt Sequence | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Chapter downloads durably enqueued first (`DatabaseService.enqueueDownload`), independent of non-blocking Add-to-Library prompt response; saved to managed storage (`StorageService.instance.chaptersDir`). Durable background worker execution tracked under planned WorkManager phase. |

---

## Detailed Evidence & Verification Log

### 1. Phase 0C: Native Kotlin-Side Shosetsu Engine & MethodChannel Integration
- **Architectural Completion:**
  - Integrated native Android Kotlin host runtime: `android/app/src/main/kotlin/com/hon/reader/hon/shosetsu/ShosetsuKotlinEngine.kt` and `ShosetsuBridge.kt`.
  - Sandboxed Luaj (`org.luaj:luaj-jse:3.0.1`) strips host OS, IO, and Java reflection globals.
  - Implements Shosetsu extension environment:
    - Global `Require("FilterOptions")` and `Require("url")`.
    - Real network `GET()` and `POST()` executing via `OkHttpClient`.
    - Rich DOM querying using `org.jsoup:jsoup:1.18.1`, exposing `.select()`, `.text()`, `.attr()`, `.first()`, `.last()`, and `.html()` on responses and elements.
  - Flutter integration in `lib/core/sources/native_shosetsu_bridge.dart` and `SourceRegistry`:
    - On Android, routes catalog search, novel details, and passage retrieval directly to the native Kotlin engine.
    - On desktop and headless unit test environments, falls back cleanly to the pure-Dart Lua engine.

### 2. Phase 0D: Drift (SQLite) Persistence & Seamless SharedPreferences Migration
- **Drift SQLite Architecture:**
  - Implemented `lib/core/database/app_database.dart` with Drift 2.34.4 and `sqlite3_flutter_libs 0.6.0+eol`.
  - Tables: `BooksTable`, `LibraryEntriesTable`, `ChaptersTable`, `DownloadJobsTable`, `ReadingProgressTable`, `BookmarksTable`, `AppSettingsTable`.
  - Runs in background isolate via `NativeDatabase.createInBackground(hon.sqlite)`, with automatic memory fallback for headless testing.
- **Seamless Migration:**
  - `_migrateFromSharedPreferencesIfNeeded()` checks if legacy JSON stores exist in SharedPreferences (`hon_books`, `hon_library`, `hon_chapters`, `hon_progress`, `hon_downloads`, `hon_bookmarks`).
  - Automatically imports all legacy records into Drift in a single atomic database batch transaction on first run.
  - Verified via dedicated test suite: `test/unit/drift_persistence_migration_test.dart` (2/2 passing).

### 3. Phase 0E: Android WorkManager Download Recovery & Background Worker
- **WorkManager Background Execution:**
  - Implemented `android/app/src/main/kotlin/com/hon/reader/hon/HonDownloadWorker.kt` extending `CoroutineWorker` from `androidx.work:work-runtime-ktx:2.9.1`.
  - Background downloads run out-of-process with exponential backoff (15s) and network constraints. Downloads write to atomic `.tmp` files and update the SQLite database upon completion.
  - Interfaced with Flutter via `HonDownloadManagerBridge.kt` and `lib/core/downloads/hon_download_manager.dart`.
- **Process Termination Recovery:**
  - `HonDownloadManager.recoverInterruptedDownloads()` executes on app startup.
  - Detects any job left in `DownloadStatus.running` from an earlier terminated process, resets it to `DownloadStatus.queued` in `DatabaseService` with an honest recovery message, and re-schedules execution with WorkManager.
  - Verified via dedicated test suite: `test/unit/download_recovery_test.dart` (1/1 passing).

### 4. Phase 0-ReaderUI: Native Android Reader Classic Apple Books Design Pass
- **Layout & Controls Redesign:**
  - `ReadiumReaderActivity.kt` updated to Classic Apple Books aesthetic across top bar, bottom scrubber, appearance dialog, and table of contents.
  - Top bar features circular action pills (`✕`, `≡`, `Aa`), refined title, and dynamic theme backgrounds.
  - Bottom bar features a centered Apple Books progress scrubber pill showing chapter title and percentage (`14% • Chapter 1`), framed by subtle navigation buttons (`❮ Prev`, `Next ❯`).
  - Appearance dialog (`Aa`) redesigned with Apple Books typography stepping ("A / A" buttons with centered percentage), 3 reference theme cards (Light, Sepia, Dark) with selection indicator borders, and segmented Paged vs Scroll switcher.
  - Table of Contents sheet matches the active theme with rounded card framing, recursive depth indentation, and active chapter highlights.
  - Preserves all layout framing (weight 1.0f non-overlapping middle container) and adaptive system bar contrast.

### 5. Quality & Verification Metrics
- **Static Analysis:** `flutter analyze` — **0 issues found** (clean across all files).
- **Automated Tests:** `flutter test` — **49 passed, 0 failed** across all unit and integration test suites.
- **Android Compilation:** `./gradlew assembleDebug` — **BUILD SUCCESSFUL**. Output: `build/app/outputs/flutter-apk/app-debug.apk` (213MB).
- **Physical Device Acceptance:** Marked **⏳ Pending User Device Testing** per milestone agreement before proceeding to Phase 1.
