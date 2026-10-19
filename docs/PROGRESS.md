# Hon — Project Implementation Progress & Requirements Matrix

> **Current release: Hon 1.1.1.** Reading History, themed launcher icon and the fuller Home pass are complete. See [current handover and APK](APP_CURRENT_2026-10-19.md). Known implementation gaps are closed; user phone acceptance is pending.

> **19 October current handover:** remaining feature implementation is complete. See [Hon 1.1.0 completion](APP_COMPLETION_2026-10-19.md) for the current APK, delivered functionality, evidence and short phone check. Earlier release links and matrices below are historical.

> Current milestone: Phase 1 UI implementation complete. See [Phase 1 completion and current release](PHASE1_COMPLETION_2026-10-18.md); phone acceptance is pending. Older phase matrices below are historical.

> **Latest:** the reported follow-up repairs, bundled Shosetsu catalog, and initial reader/Home/settings visual pass are implemented. See [REPAIR_AND_DESIGN_HANDOVER_2026-10-18.md](REPAIR_AND_DESIGN_HANDOVER_2026-10-18.md) for the current release artifact and manual acceptance boundary. Earlier milestone descriptions below are historical.

> **18 October follow-up:** functional code and APK handover have been updated.
> The user is handling manual acceptance. See the current status document and
> PHASE0_MANUAL_CHECKLIST.md. Historical checkmarks below are not a current
> Phase 0 sign-off. The final implementation adds adjacent-resource EPUB
> scrolling and a broader bounded Shosetsu core host; device acceptance is pending.

> This matrix records earlier implementation claims and has not been fully
> revalidated on the current APK. For the latest tested changes, limits, and
> pending Android acceptance, see
> [PHASE0_IMPLEMENTATION_STATUS_2026-10-18.md](PHASE0_IMPLEMENTATION_STATUS_2026-10-18.md).

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
| **Downloads & Updates** | Integrity & Prompt Sequence | ✅ | ✅ | ✅ | ⏳ **Pending Next APK Test** | Chapter URL and managed destination path persisted in SQLite (`chapters_table`) before scheduling WorkManager. Non-blocking Add-to-Library prompt triggered independently. Background execution handled solely by WorkManager without competing foreground downloads. |
| **Native Engine / Stability** | ProGuard R8 Rules & Startup Self-Check (Phase A) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | R8 keep rules preserve LuaJ, Jsoup, Readium, Drift/SQLite, OkHttp, and WorkManager reflection. Startup self-check runs on launch to verify VM compatibility. |
| **Native Sandbox / Security** | String Metatable Ordering & CPU Budget (Phase A) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | StringLib loads prior to `SandboxStringMethods.enter` preventing protection regression; instruction counter budgeting prevents thread stalls. |
| **Network Security** | Source Host Allowlist & Redirect Validation (Phase B1) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | OkHttp interceptor enforces declared source baseURL and user-whitelisted domains; unauthorized redirect chains blocked; UI controls for allowed hosts. |
| **Persistence (Drift SQLite)** | Schema v2 -> v3 Migration (Phase B2) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | Zero-loss schema migration adding `CollectionsTable`, `CollectionMembershipsTable`, `ChapterUpdateHistoryTable`, `HighlightsTable`, and `BookReaderSettingsTable`. |
| **Database Performance** | Lazy Chapter Loading & SQL Aggregates (Phase B3) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | Lazy `loadChapters` replaces whole-database chapter caching in memory; SQL aggregates compute downloaded chapter counts efficiently. |
| **Updates & Concurrency** | Source-Serial Concurrency Pool (Phase B4) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | Max 2 concurrent novel checks globally, strictly serialized per `sourceId` to protect upstream source servers. |
| **Chapter Identity & Healing** | Multi-Pass Reconciliation (Phase B5) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | 3-pass chapter identity reconciliation (sourceId -> title -> index) healing reading progress and preserving downloaded chapter state across upstream renames. |
| **Download Storage Hygiene** | Content-Addressed SHA-256 Illustrations (Phase B6) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | Downscaled image cache with content-addressed SHA-256 filenames inside `imagesDir`, validating MIME magic bytes. |
| **Reader Features** | Highlights & Annotations (Phase C1) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | Text selection highlights with notes, persisted in SQLite `highlights_table`, managed via Reader Contents sheet "Highlights" tab. |
| **Reader Features** | Per-Book Reader Overrides (Phase C2) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | Per-book typography, theme, and layout overrides persisted in `book_reader_settings_table` with "Reset to Defaults" option. |
| **Reader Features** | Locator-Based Bookmarks (Phase C3) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | Precise locator-based bookmarking anchored to chapter and block offsets. |
| **Readium EPUB Guard** | Fixed-Layout Warning & Reflow Guard (Phase C4) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | Detects fixed-layout EPUBs, suppresses continuous scroll toggle, and presents a non-intrusive warning dialog. |
| **Reader Features** | Publisher Typography Switch (Phase C5) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | Toggle publisher-specified styling vs Hon custom typography with confirmation dialog. |
| **Build & Packaging** | ABI Splits & 16KB Page Size Compliance (Phase D1) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | ABI splits for `armeabi-v7a`, `arm64-v8a`, `x86_64` + universal APK; removed `google_fonts` and EOL `sqlite3_flutter_libs`; migrated to modern `sqlite3: ^3.3.0` compliant with Android 15 16KB page sizes. |
| **Licensing & Compliance** | Open Source Licensing Audit (Phase D2) | ✅ | ✅ | ✅ | ✅ **Verified** | Created `docs/LICENSING.md` documenting GPL-3.0 Shosetsu bundled Lua scripts, SIL OFL 1.1 typefaces, and permissive native libraries. |
| **UI & Design System** | Liquid Glass Appearance & Accessibility (Phase D3) | ✅ | ✅ | ✅ | ⏳ **Needs Phone Check** | Subtle vs Full glass styling modes with high-contrast fallback across navigation bars, sheets, and headers. |

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

### 5. Phase A: Release Crash Fixes & Engine Stability
- **ProGuard R8 Protection Rules:**
  - Configured `android/app/proguard-rules.pro` with explicit `-keep` directives for LuaJ reflection (`org.luaj.vm2.**`), Jsoup DOM models (`org.jsoup.**`), Readium toolkit (`org.readium.r2.**`), Drift SQLite runtime (`org.sqlite.**`), OkHttp interceptors, and WorkManager reflection.
- **Engine Startup Self-Check:**
  - Implemented `ShosetsuKotlinEngine.runStartupCheck()` executed at native bootstrap, verifying Lua bytecode execution, table returns, and string metatable hooks before accepting user queries.
- **Lua Metatable Protection Ordering:**
  - Resolved `SandboxStringMethods.enter(globals)` ordering regression: ensures `StringLib()` loads strictly *before* sandbox string metatables are patched so string sandboxing cannot be overridden by standard library initialization.
- **Instruction-Count Budgeting:**
  - Replaced time-polling loops with instruction counter budgets in `BudgetDebugLib`, neutralizing infinite loops without thread starvation or premature timeouts.
- **Catalog Reinstallation:**
  - Automated asset cache resynchronization to reinstall bundled source catalogs seamlessly on upgrade.

### 6. Phase B: Functional Hardening & Integrity
- **Host Allowlisting & Redirect Policy (B1):**
  - Implemented `SourceNetworkPolicy.kt` OkHttp network interceptor restricting outbound requests to declared source `baseUrl` and user-configured hostnames in `source_controls_screen.dart` (ADR-010). Blocks unauthorized cross-domain redirect chains.
- **Drift Schema v2 -> v3 Migration (B2):**
  - Seamless migration adding `CollectionsTable`, `CollectionMembershipsTable`, `ChapterUpdateHistoryTable`, `HighlightsTable`, and `BookReaderSettingsTable` with dual-persistence read/write synchronization and zero user data loss.
- **Lazy Chapter Loading & SQL Aggregates (B3):**
  - Replaced in-memory global chapter lists with on-demand `loadChapters()` and SQL aggregate queries (`ensureChaptersLoaded`, `_downloadedCounts`), drastically reducing memory footprint for large library collections.
- **Serial Concurrency Pool (B4):**
  - Implemented global semaphore pool: max 2 concurrent novel checks globally, strictly serialized per `sourceId` to avoid overwhelming upstream servers.
- **Chapter Identity & Reading Progress Healing (B5):**
  - 3-pass reconciliation algorithm (Pass 1: exact `sourceChapterId`, Pass 2: normalized title, Pass 3: index fallback), preserving downloaded states, file paths, and reading progress `lastChapterId` across upstream novel updates.
- **Downscaled Image Hygiene (B6):**
  - Content-addressed SHA-256 filenames inside `imagesDir`, validating image MIME magic bytes and downscaling large chapter illustrations to prevent OOMs.
- **Offline Test Gating (B7):**
  - Gated live upstream tests with explicit `skip` logic when offline, ensuring test suites fail on real network errors when enabled without masking regressions.

### 7. Phase C: Reader Experience & Missing Features
- **Highlights & Annotations (C1):**
  - Text selection "Highlight" and "Add Note" actions in `ReaderScreen`, persisted in Drift `HighlightsTable`, surfaced in `ReaderContentsSheet` under a dedicated "Highlights" tab with navigation and deletion support.
- **Per-Book Reader Overrides (C2):**
  - Independent typography, theme, and layout settings persisted per book in `BookReaderSettingsTable`. Accessible via `ThemesSettingsSheet` with a "Reset to Defaults" option to revert to global preferences.
- **Locator-Based Bookmarks (C3):**
  - Enhanced bookmark model supporting `locatorString` and `locatorVersion: '1'`, anchoring bookmarks to specific chapter resources and text block offsets.
- **Fixed-Layout EPUB Safety Guard (C4):**
  - `ReadiumReaderActivity.kt` detects fixed-layout publications, suppresses unsupported continuous scroll toggles, and presents an informative warning dialog.
- **Publisher Typography Mode (C5):**
  - Toggle between publisher-specified CSS typography and Hon custom reader typography with user confirmation.

### 8. Phase D: Packaging Hygiene & Design System
- **ABI Splits & 16KB Page Size Compliance (D1):**
  - Configured ABI splits (`armeabi-v7a`, `arm64-v8a`, `x86_64`) plus universal APK in `android/app/build.gradle.kts`.
  - Removed unused `google_fonts: ^6.2.1` and EOL `sqlite3_flutter_libs: ^0.6.0+eol`.
  - Upgraded to modern `sqlite3: ^3.3.0` utilizing Dart Native Assets, fully compliant with Android 15 16KB memory page sizes.
- **Open Source Licensing Audit (D2):**
  - Authored `docs/LICENSING.md` documenting upstream GPL-3.0 Shosetsu bundled Lua scripts, SIL OFL 1.1 typography, and permissive MIT/Apache-2.0 dependencies.
- **Liquid Glass UI System (D3):**
  - Refined Liquid Glass UI in `GlassSurface`, `AppAppearanceSection`, and `tab_scaffold.dart`, supporting Subtle (default) and Full glass styling with automatic high-contrast accessibility fallback.

### 9. Recent Source Fixes, Data Integrity & UI Refinements (October 2026)
- **1stKissNovel SSL Trust Anchor & Host Policy:**
  - Diagnosed `CertPathValidatorException: Trust anchor for certification path not found` caused by missing intermediate cross-cert `ISRG Root YR` in server handshake. Added genuine self-signed `root-yr.pem` (`ISRG Root YR`) into `android/app/src/main/res/raw/isrg_root_yr.crt` and app trust anchors in `network_security_config.xml`. Verified with OpenSSL: `Verify return code: 0 (ok)`.
  - Added dynamic catalog permission upgrade: existing installs receive catalog host permission updates (`1stkissnovel.love`, `gregariousfrog.com` for MCStories) without reinstalling or resurrecting deleted sources.
  - Upgraded source error screen with categorized friendly messages, a prominent Retry button, and an expandable copyable Technical Details container.
- **Data Integrity & Reconciliation:**
  - Chapter reconciliation: strictly rejects ambiguous non-unique title matches and position-only file transfers; preserves unresolved downloads safely.
  - Backup restoration: rewrites local image URLs in restored chapter HTML to point to relocated image storage directories.
  - Collections SQL export/import: transactional SQLite collection snapshot export and import with backward-compatible legacy preference migration.
  - Offline image processing guard (`OfflineChapterImages.kt`): implemented `processImage` returning `ProcessedImage` with validated dimensions (`outWidth > 0 && outHeight > 0`). When scaled, encodes PNG for non-JPEG formats and updates MIME (`image/png`) and extension (`.png`). Catches decode errors and treats missing images gracefully. Bitmaps safely recycled.
- **Source Icons & Browsing:**
  - Added `iconUrl` support to `RepositoryScript`, `InstalledExtension`, and `ExtensionMeta`.
  - Updated `BundledSourceCatalog.seed` to enrich bundled sources with repository script icon URLs.
  - Added `_buildSourceAvatar` in `browse_screen.dart` with network image and letter fallback for both installed sources and repository extensions.
- **Liquid Glass Navigation & UI Refinements:**
  - Bottom navigation: single moving glass capsule indicator with spring animation (`Curves.easeOutBack`) and tactile press feedback (`scale: 0.92`), replacing separate in-place pill animations.
  - Restored solid `#000000` pure black dark background (eliminated gradient wash) and `#F2F2F7` light background.
  - Grouped Continue Reading section on Home with `GlassSurface` framing, Newsreader serif typography, and bounded responsive card height.
  - Refined Calm theme palette across Flutter (`reader_theme.dart`) and native Readium (`ReadiumReaderActivity.kt`) to match the user's Apple Books reference screenshot: `#F1E5CD` warm background, `#2C2211` text, `#70624E` secondary text, `#E8DCBF` controls.
  - Clean "Reset to defaults" in Readium reader resetting settings to global defaults without immediately re-saving a book override in SQLite.
- **Direct Physical Device Deployment & Packaging:**
  - Built `app-arm64-v8a-release.apk` (30 MB) and copied to `./hon-arm64-v8a-release.apk`, signed with local keystore (`-PhonLocalSigning=true`) for direct installation over existing installs.

### 10. Quality & Verification Metrics
- **Static Analysis:** `flutter analyze` — **0 issues found** (clean across all files).
- **Kotlin JVM Unit Tests:** `./gradlew :app:testDebugUnitTest` — **passed** (100% pass rate across engine, sources, network policy, and image tests).
- **Flutter Automated Unit Tests:** `flutter test test/unit/` — **86 passed, 0 failed** (100% pass rate across drift migration, chapter reconciliation, source catalog, download recovery, reader document, and font suites).
- **Release APK:** `hon-arm64-v8a-release.apk` (30 MB, arm64-v8a) assembled and ready for device testing.

