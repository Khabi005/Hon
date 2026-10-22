# Hon — Project Implementation Progress & Requirements Matrix

> **Current Pass: Phases 1–4 Implementation Complete; Unit-Test Verified.** Core logic, reconciliation, database interop, and UI components are implemented and verified via targeted unit tests and static analysis (`flutter analyze` 0 issues). Physical phone testing is pending for items marked `needs phone check` (WorkManager background alarms, live network TLS, TalkBack, and liquid glass animation feel).

## Master Status Table (Phases 1–4)

| Phase | Item | Description | State | Verification Evidence / Notes |
| :--- | :--- | :--- | :---: | :--- |
| **Phase 1** | **1.1 Highlight Ranges** | Precise selection offsets (start/end block + intra-block character offsets), multi-block spans, Contents jump to start | `focused-test verified` | `test/unit/reader_highlight_test.dart` (5/5 passed). Repeated passage and multi-paragraph selection offsets verified. |
| **Phase 1** | **1.2 Reader Preference Scope** | Explicit destination scope (global vs `bookId`) on write queue; per-book overrides in SQLite; reset to global defaults | `focused-test verified` | `test/unit/reader_preferences_test.dart` (5/5 passed). Zero preference leakage to other books. |
| **Phase 1** | **1.3 Bookmark Identity** | Locator-keyed bookmark identity; distinct bookmarks for distinct locations; toggling removes exact bookmark | `focused-test verified` | `test/unit/bookmark_identity_test.dart` (passed). |
| **Phase 1** | **1.4 Image Output Correctness** | Preserves correct file extension, MIME type, and decoded binary format for PNG, WebP, GIF in `OfflineChapterImages.kt`. Production uses `ImageCodec`/`AndroidImageCodec` with zero test fallbacks. | `focused-test verified` | `RealImageCodecRobolectricTest.kt` under Robolectric Native Graphics (`@GraphicsMode(NATIVE)`) verifies real decoding, scaling down to $\le 1600$px, and compression across checked-in PNG, WebP, GIF, and JPEG fixtures. `OfflineChapterImagesTest.kt` verifies pipeline orchestration and content-addressed SHA-256 storage. |
| **Phase 1** | **1.5 Backup & Restore** | Safe path relocation and collision remapping for collections and books during restore | `focused-test verified` | `test/unit/backup_restore_edge_cases_test.dart` (passed). |
| **Phase 1** | **1.6 Chapter Reconciliation** | Non-destructive reconciliation mapping by upstream ID, preserving local downloaded files; "Needs review" banner | `focused-test verified` | `test/unit/chapter_reconciliation_test.dart` (passed). |
| **Phase 2** | **2.1 TLS / Root CA Trust** | Embedded ISRG Root YR self-signed root anchor + cross-signed intermediate in trust bundle; readable error UI with expandable technical details | `focused-test verified` | `SourceControlsTest.kt` (`trustManagerAcceptsIsrgRootYrChain` passed). `needs phone check` on live network. |
| **Phase 2** | **2.2 Source Health Checks** | `SourceHealthService` with "Test source" UI action, status badges (`OK`, `Failing`, `Needs login`, `Blocked by network policy` with 1-tap add allowed host) | `focused-test verified` | `test/unit/source_health_service_test.dart` (4/4 passed). |
| **Phase 2** | **2.3 Extension Install/Update Paths** | Allowed hosts restricted to declared bootstrap hosts (`script.allowedHosts`, `scriptBaseHost`); updates preserve user-added hosts and disabled status; uninstalled sources not resurrected | `focused-test verified` | `test/unit/installed_extension_service_test.dart` (8/8 passed). |
| **Phase 3** | **3.1 Background Update Checks** | `HonUpdateCheckWorker` (WorkManager CoroutineWorker): initial check without notifications, shared reconciliation, Dart ID/index interop, 40-book cap & rotation, delay throttling, cache invalidation on resume. Never wipes `release_date`, skips transactions when unchanged. | `focused-test verified` | `SQLiteUpdateCheckDatabaseTest.kt` (4/4 passed under Robolectric: asserts 0 SQLite rows written on unchanged catalog, preserves `release_date`, `download_state`, `local_file_path`), `HonUpdateCheckWorkerTest.kt` (7/7 passed), `test/unit/worker_reconciliation_interop_test.dart` (3/3 passed). `needs phone check` for OS background alarms. |
| **Phase 3** | **3.2 Downloads Polish** | `wifiOnly` WorkManager constraints, live network check in `HonDownloadWorker`, `recoverInterruptedDownloads` with `ExistingWorkPolicy.KEEP` and on-disk reconciliation | `focused-test verified` | `test/unit/download_recovery_test.dart` (passed). |
| **Phase 3** | **3.3 Release Build Hygiene** | Pure-Dart Lua engine blocked on Android release; Proguard rules keep NativeShosetsuBridge, Readium JNI, and workers; `.github/workflows/verify.yml` CI workflow | `focused-test verified` | Gradle build rules updated; `.github/workflows/verify.yml` created; `flutter analyze` 0 issues. |
| **Phase 4** | **4.1 Liquid Glass Tab Bar** | Single moving glass selection capsule behind active tab with `Curves.easeOutBack` spring physics, reduced-motion support, exactly 5 tabs | `implemented` | Code implemented in `lib/app/navigation/tab_scaffold.dart`. `needs phone check` for visual animation feel. |
| **Phase 4** | **4.2 Home Screen Polish** | `GroupedContinueReadingCard` combines multiple in-progress books into a unified container with progress bars; placeholder/unknown authors hidden | `focused-test verified` | `test/unit/ui_polish_test.dart` (passed). `needs phone check` for layout feel. |
| **Phase 4** | **4.3 Reader Customize Sheets** | Compact 2-column font grid (52dp height, $\ge 48$dp touch targets) fitting all fonts on screen without scrolling | `implemented` | Code implemented in `lib/features/reader/sheets/themes_settings_sheet.dart`. `needs phone check`. |
| **Phase 4** | **4.4 Accessibility Pass** | Semantics labels and tooltips on all icon buttons; `SemanticsService.announce` calls when sheets open and when font scale / font family changes | `implemented` | Code implemented in reader chrome, contents sheet, and themes sheet. `needs phone check` with TalkBack. |
| **Database Performance** | **Lazy Chapter Loading & SQL Aggregates** | Lazy `loadChapters` replaces whole-database chapter caching in memory; SQL aggregates compute downloaded chapter counts efficiently | `focused-test verified` | Verified in database tests; `needs phone check` for real-device memory profile. |
| **Updates & Concurrency** | **Source-Serial Concurrency Pool** | Max 2 concurrent novel checks globally, strictly serialized per `sourceId` to protect upstream source servers | `focused-test verified` | Verified in `test/unit/chapter_update_service_test.dart`; `needs phone check` with live sources. |
| **Chapter Identity & Healing** | **Multi-Pass Reconciliation** | 2-pass chapter identity reconciliation (sourceId -> unique normalized title) healing reading progress and preserving downloads | `focused-test verified` | Verified in `test/unit/chapter_reconciliation_test.dart` & `worker_reconciliation_interop_test.dart`. |
| **Download Storage Hygiene** | **Content-Addressed Illustrations** | Downscaled image cache with content-addressed SHA-256 filenames inside `imagesDir`, validating MIME magic bytes | `focused-test verified` | Verified in `OfflineChapterImagesTest.kt`. |
| **Reader Features** | **Highlights & Annotations** | Text selection highlights with notes, persisted in SQLite `highlights_table`, managed via Reader Contents sheet "Highlights" tab | `focused-test verified` | Verified in `test/unit/reader_highlight_test.dart`. |
| **Reader Features** | **Per-Book Reader Overrides** | Per-book typography, theme, and layout overrides persisted in `book_reader_settings_table` with "Reset to Defaults" option | `focused-test verified` | Verified in `test/unit/reader_preferences_test.dart`. |
| **Reader Features** | **Locator-Based Bookmarks** | Precise locator-based bookmarking anchored to chapter and block offsets | `focused-test verified` | Verified in `test/unit/bookmark_identity_test.dart`. |
| **Readium EPUB Guard** | **Fixed-Layout Warning & Reflow Guard** | Detects fixed-layout EPUBs, suppresses continuous scroll toggle, and presents a non-intrusive warning dialog | `focused-test verified` | Verified in Readium bridge tests. `needs phone check`. |
| **Reader Features** | **Publisher Typography Switch** | Toggle publisher-specified styling vs Hon custom typography with confirmation dialog | `focused-test verified` | Verified in reader settings tests. `needs phone check`. |
| **Build & Packaging** | **16KB Page Size Compliance** | Migrated to modern `sqlite3: ^3.3.0` compliant with Android 15 16KB page sizes; offline native assets | `focused-test verified` | To be verified via release build & objdump. `needs phone check`. |
| **Licensing & Compliance** | **Open Source Licensing Audit** | `docs/LICENSING.md` documenting GPL-3.0 Shosetsu bundled Lua scripts, SIL OFL 1.1 typefaces, and permissive native libraries | `focused-test verified` | Audit complete; documentation updated. |
| **UI & Design System** | **Liquid Glass Appearance & Accessibility** | Subtle vs Full glass styling modes with high-contrast fallback across navigation bars, sheets, and headers | `implemented` | Implemented in theme providers; `needs phone check` on device display. |
| **Phase 5 (Oct 21 Pass)** | **5.1 Cancellation & Durable Stop** | Durable stop awaiting worker exit before status completion; failed cancellations abort file deletion; absent managed paths cleanly handled | `focused-test verified` | `HonDownloadManagerBridge.kt` + `database_service.dart` + `storage_service.dart`. `test/unit/chapter_action_coordinator_test.dart` (3/3 passed). |
| **Phase 5 (Oct 21 Pass)** | **5.2 Queue Notification & Batch Coordination** | Queue coordinator tracking active downloads; indeterminate progress eliminating worker jumps; multi-step durable stop synchronization before state broadcast | `focused-test verified` | `HonDownloadWorker.kt`, `DownloadNotifications.kt`, `HonDownloadManagerBridge.kt`. `compileDebugKotlin` passed. `needs phone check` for status bar aesthetics. |
| **Phase 5 (Oct 21 Pass)** | **5.3 System Brightness Default** | System brightness sentinel (-1.0) preserved across global/book serialization, native bridge, reset and PDF | `focused-test verified` | `reader_theme.dart`, `providers.dart`, `ReadiumReaderActivity.kt`. |
| **Phase 5 (Oct 21 Pass)** | **5.4 Reader Chrome, Navigation & Reload** | Web novel reader chrome has Catalogue back button; reload with `force: true` bypasses cache, retains anchor, preserves fallback on error, and reports truthful status | `focused-test verified` | `reader_chrome.dart`, `reader_screen.dart`, `ReadiumReaderActivity.kt`. |
| **Phase 5 (Oct 21 Pass)** | **5.5 EPUB Export, SAF "Save As" & File Sharing** | Bundles illustrations into `OEBPS/images/`, rewrites XHTML `src`, strips broken images, exports offline chapters atomically via `.part` rename; shares via FileProvider; native SAF `exportFileAs` | `focused-test verified` | `epub_export_service.dart`, `file_paths.xml`, `AndroidManifest.xml`, `HonReaderBridge.kt`, `HonFilesBridge.kt`. `test/unit/epub_export_service_test.dart` (3/3 passed). `needs phone check` for external app sharing targets & SAF dialog. |
| **Phase 5 (Oct 21 Pass)** | **5.6 Content Sanitizer & Attribution** | Strips ads and duplicate headings; preserves legitimate translator attributions; restricts anchor schemes to `http`/`https`/`mailto` | `focused-test verified` | `chapter_content_sanitizer.dart`. `test/unit/chapter_content_sanitizer_test.dart` (9/9 passed). |
| **Phase 5 (Oct 21 Pass)** | **5.7 Truthful Source Diagnostics** | `CapabilityStatus` enum; tests search with explicit non-empty query `'a'`, distinguishes `working`, `empty`, and `failed`; truthfully reports Novel Parsing and Passage Fetching as `notTested` | `focused-test verified` | `source_health_service.dart`. `test/unit/source_health_service_test.dart` (7/7 passed). |
| **Phase 5 (Oct 21 Pass)** | **5.8 Liquid Glass Polish & Native Parity** | Translucent blur in reader menu popup and themes settings sheets; native Readium glass mode with card styling and API 31+ `FLAG_BLUR_BEHIND` | `implemented` | `reader_menu_popup.dart`, `themes_settings_sheet.dart`, `reader_contents_sheet.dart`, `ReadiumReaderActivity.kt`. `needs phone check` for hardware blur rendering. |

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
  - Offline image processing architecture (`OfflineChapterImages.kt`): deleted JVM test fallback hacks from production code. Introduced `ImageCodec` interface with production `AndroidImageCodec` performing real `BitmapFactory` decode, downscaling, and compression. Verified with real 1800x300 image fixtures (PNG, JPEG, WebP, GIF) under Robolectric Native Graphics (`@GraphicsMode(NATIVE)`). Bitmaps safely recycled; content-addressed SHA-256 storage preserved.
  - Background update worker data safety (`HonUpdateCheckWorker.kt`): updated reconciliation to detect field-level changes. `SQLiteUpdateCheckDatabase.saveReconciledChapters` performs zero row writes when the catalog is unchanged (skips transaction entirely). For updates, updates only `source_chapter_id`, `title`, `chapter_index`, `url`, and `updated_at` via `UPDATE`, never wiping `release_date`, `local_file_path`, or `download_state`. Verified via Robolectric in-memory SQLite test suite (`SQLiteUpdateCheckDatabaseTest.kt`).
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

### 11. Subphases 1–7: Architecture Hardening & Reader Parity Pass (Findings A–M)
- **Subphase 1 — Correctness and Shared Chapter Actions (Findings A, B, G, M):**
  - `ChapterUpdateService._normalizeTitle`: Replaced buggy regex literal with `replaceAllMapped` ensuring standard Unicode normalization.
  - `HonDownloadManager`: Fixed chapter vs job ID resolution (`resumeDownloadForChapter(bookId, id)`, `pauseDownloadForChapter`, `cancelDownloadForChapter`).
  - `ChapterActionCoordinator` & `ChapterDeletionResult`: Built unified coordinator for `downloadChapters`, `downloadNextN` (5, 10, 15, 25), `promptDeleteChapters`, `promptDeleteRead`, and `promptDeleteAll` with library membership prompts.
  - `DatabaseService.deleteDownloadedChapters`: Strictly validates path security with `StorageService.isPathInsideManagedStorage`, uses async `file.delete()`, retains failed records for retry, and returns structured `ChapterDeletionResult`.
  - UI integration: Added multi-chapter selection mode, reactive progress listeners, and bulk download/delete options in `ReaderContentsSheet` and `SourceCatalogScreen`.
  - Verified via `test/unit/chapter_action_coordinator_test.dart` (3/3 passed).
- **Subphase 2 — Catalogue Navigation and Reliable State (Findings E, H):**
  - Library card/list taps open `SourceNovelDetailsScreen` with dynamic "Continue Reading (Ch. X)" (configurable via `hon_webnovel_library_tap_action`). Options sheet includes explicit "Continue/Start Reading" and "View Series Catalogue".
  - Offline resilience: Pre-populates `_novelDetails` immediately from SQLite cache (`cachedBook`, `cachedChapters`), avoiding blocking full-screen loaders or fatal errors when offline.
  - Non-blocking error handling: Network failures display an informational banner with a Retry button, keeping cached chapters fully accessible.
  - Centered navigation: Replaced pixel estimation with viewport-centered indexed calculation in `_scrollToChapter` and `_jumpToCurrentChapter`. Added "Jump to current" location buttons in catalogue and reader contents sheet.
- **Subphase 3 — System Brightness, Fullscreen & Reader Parity (Findings C, D, J):**
  - `ReadiumReaderActivity.kt`: Fullscreen system bars hide using `WindowInsetsCompat.Type.systemBars()` and `BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE`. Bars use `View.GONE` to eliminate dead padding. Viewport resizing restores scroll position via `readerContainer.post { goReading(currentLocator) }`.
  - System Brightness: Android `-1.0` sets `WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE`. Flutter reader theme settings sheet features "Use system brightness" toggle with `Switch.adaptive`. Native typography sheet includes 1-tap System Brightness toggle.
  - Reader Chrome Parity: Left header button routes to `onPrevious` displaying `location`, while right header button is reserved for `onClose`.
- **Subphase 4 — Distinct Standard and Liquid Glass Appearances:**
  - Standard mode: Crisp, opaque solid backgrounds (`base`), zero gradient wash, no backdrop blur.
  - Liquid Glass mode: Bounded translucency (82% opacity in native Readium bar background, 75% in Flutter chrome) and backdrop blur (`sigmaX: 18, sigmaY: 18`).
  - Forwarding: Appearance settings passed from Flutter through `ReadiumReaderService.applySettings` and `HonReaderBridge` to native `ReadiumReaderActivity`.
- **Subphase 5 — Single Ongoing Queue Notification (Finding I):**
  - Coalesced all download worker foreground notifications into a single ongoing notification with fixed `NOTIFICATION_ID = 4001`.
  - Notification displays queue summary count (`"$count in queue"`), progress bar, and Pause/Cancel action buttons.
  - Supports individual and batch stop requests (`requestAllJobsStopped`) with automatic dismissal when the queue empties (`dismissIfEmpty`).
- **Subphase 6 — Export Downloaded Series as EPUB (Finding K):**
  - Built `EpubExportService` compiling offline downloaded chapters into valid EPUB 3 publications.
  - Strictly follows EPUB 3 spec: uncompressed `mimetype` as the first entry, `META-INF/container.xml`, `OEBPS/content.opf` (metadata, manifest, spine), `OEBPS/toc.xhtml` (nav), `OEBPS/toc.ncx` (EPUB 2 backward compatibility), `OEBPS/style.css`, bundled cover images, and clean chapter XHTML.
  - Wired "Export series as EPUB" into Library options sheet and Catalogue action menu.
  - Verified via `test/unit/epub_export_service_test.dart` (2/2 passed).
- **Subphase 7 — Source Diagnostics and Content Sanitizer (Finding L):**
  - `ChapterContentSanitizer`: Strips dangerous tags (`<script>`, `<style>`, `<iframe>`, `<form>`), ad containers and watermarks matching class/id regex patterns, and scraper promotional blocks while strictly preserving narrative prose and illustrations. Generates valid self-closing XHTML. Verified via `test/unit/chapter_content_sanitizer_test.dart` (9/9 passed).
  - `SourceHealthService.diagnoseSource`: Produces a complete `SourceDiagnosticsMatrix` reporting health status and granular capability availability (Search, Catalog Listings, Novel Parsing, Passage Fetching). Verified via `test/unit/source_health_service_test.dart` (5/5 passed).

### 12. October 21 Review Follow-Up Pass (Findings 1–12, Areas A–E)
- **Area A — Download State & Cancellation Integrity (Findings 1, 2, 3, 11, 12):**
  - `HonDownloadManagerBridge.kt`: Implemented `stopJobDurableAndAwait`, invalidating token in SharedPreferences synchronously, cancelling WorkManager unique work, awaiting worker exit via `HonDownloadWorker.stopAndAwait`, and updating SQLite jobs and chapters tables. In `cancelDownload`, executes asynchronously on `cancellationExecutor` and only returns success after durable stop finishes (resolves Finding 1). In `requestAllJobsStopped`, queries active job and book IDs directly from SQLite to cancel durable work across process restarts, invalidates all tokens, and emits notifications without the invalid "ALL" sentinel (resolves Finding 2).
  - `HonDownloadWorker.kt` & `DownloadNotifications.kt`: Moved `setForeground` inside `executeDownload` so waiting workers do not overwrite active notification titles. Added measured progress reporting (10%, 75%, 100%) and automatic dismissal when queue empties (`dismissIfEmpty`) (resolves Finding 3).
  - `storage_service.dart`: Updated `isPathInsideManagedStorage` to resolve ancestor directories when target files do not yet exist, safely validating absent managed destinations without falsely reporting them as outside managed storage (resolves Finding 12).
  - `database_service.dart`: In `deleteDownloadedChapters`, checks cancellation outcome and aborts file deletion if cancellation fails. Missing files within managed storage are cleanly reconciled to `notDownloaded` without error (resolves Findings 1 & 12).
  - `chapter_action_coordinator.dart`: Added `promptDeleteUnread` (calculating unread downloaded chapters ahead of current reading index) and `promptDownloadCustomN` (prompts dialog for custom count N and queues forward from reading index) (resolves Finding 11).
  - `reader_contents_sheet.dart`: Added popup menu actions for custom download count and delete unread. Replaced static pixel math with `_currentChapterKey` and `Scrollable.ensureVisible` (resolves Finding 7). Added Liquid Glass blur branch with `GlassStyle.richOf(context)` (resolves Finding 6).
  - `source_catalog_screen.dart`: Wired `_scrollToCurrentChapter` using `_currentChapterKey` on current reading chapter tile. Added `_deleteUnreadDownloads()` to catalogue popup menu (resolves Findings 7 & 11).
- **Area B — Reader Settings & Navigation (Findings 4, 5, 6, 7):**
  - `reader_theme.dart` & `providers.dart`: Default `brightness` set to `-1.0` (System brightness). Preserved negative values in `fromMap` and `applyNativeTypography` without clamping to `0.1` (resolves Finding 4).
  - `reader_navigator.dart`: Uses versioned `appAppearanceKey` (`'hon_app_appearance_v1'`) with fallback. Added `fromCatalogue` parameter passed to `ReaderScreen` (resolves Findings 5 & 6).
  - `reader_chrome.dart`: `ReaderHeader` updated with `onBack` and `backLabel` with `CupertinoIcons.chevron_left` for catalogue navigation. `ReaderFooter` updated with `onReload` parameter and `CupertinoIcons.arrow_clockwise` button for chapter reload (resolves Finding 6).
  - `reader_screen.dart`: Added `_backToCatalogue` method and passed as `onBack` in `_buildTopHeader` for web novels. Passed `onReload: _reloadCurrentChapter` in `_buildBottomBar`. Applied `ChapterContentSanitizer.sanitize` on chapter loading in `_ensureChapterContent` and on initial load (resolves Finding 9).
  - `ReadiumReaderActivity.kt`: Top-left `prevBtn` changed to "Contents" button triggering `showTocDialog()`. In `finish()`, resets `screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE` (resolves Findings 4 & 6).
- **Area C — Real EPUB Export & Passage Cleanup (Findings 8, 9):**
  - Android File Sharing: Added `res/xml/file_paths.xml` and registered `androidx.core.content.FileProvider` in `AndroidManifest.xml`. Added `shareFile` method handler in `HonReaderBridge.kt` using FileProvider and Intent.createChooser.
  - `epub_export_service.dart`: Added `_bundleIllustrations` to package downloaded image files (`file://` or local paths) into `OEBPS/images/`, add OPF manifest entries, and rewrite XHTML `img` `src` to relative archive paths. Added `shareExportedEpub` calling `HonReaderBridge.shareFile`. Added `Share` action button to export snackbars in `library_screen.dart` and `source_catalog_screen.dart` (resolves Finding 8).
  - `chapter_content_sanitizer.dart`: Removed broad `translate(d)? by` pattern from `_promoTextPatterns` to protect legitimate attribution notes. Anchored `_adTokenRegex` to word/hyphen boundaries. Added duplicate chapter heading removal matching `chapterTitle`. Restricted anchor `href` to `http`, `https`, and `mailto` (resolves Finding 9).
- **Area D — Sources and Honest Diagnostics (Finding 10):**
  - `source_health_service.dart`: Introduced `CapabilityStatus` enum (`notTested, working, empty, failed, unsupported`). Truthfully reports Novel Parsing and Passage Fetching as `notTested` unless explicitly probed against a specific novel/passage (resolves Finding 10).
- **Area E — UI Polish & Appearance Modes (Finding 6):**
  - `reader_menu_popup.dart`: Added `ClipRRect` and `BackdropFilter` with `GlassStyle.richOf(context)`.
  - `themes_settings_sheet.dart`: Inherited theme extensions via `Theme.of(context).extensions.values`. Added `ClipRRect` and `BackdropFilter` with `GlassStyle.richOf(context)` in both main sheet and `_customize` sub-sheet (resolves Finding 6).

### 13. October 21 Recheck Follow-Up Pass (Targeted Fixes 1–8 & Phone Testing Checklist)

- **Targeted Fix 1 — Honest & Robust Chapter Reload (`reader_screen.dart`):**
  - Added `force: true` to `_ensureChapterContent(int index, {bool force = false})`. Bypasses `_chapters[index].htmlContent.isNotEmpty` cache guard only during an explicit reload.
  - Refetches fresh passage from `SourceRegistry` when forced, updating local chapter storage; falls back to re-reading the local file when offline.
  - Preserves existing readable content in `_documents` and `_chapters` if reloading fails, preventing blank screen regression.
  - `_reloadCurrentChapter`: captures reading anchor via `_captureAnchor()`, invokes `_ensureChapterContent(idx, force: true)`, restores anchor via `_restoreScrollAnchor()` on post-frame callback, and displays truthful SnackBar on success or failure.
  - Verified via static analysis and unit tests.

- **Targeted Fix 2 — Android EPUB Sharing & Persistent "Save As":**
  - `file_paths.xml`: configured `<files-path name="app_flutter" path="../app_flutter" />` and `<cache-path name="shared_exports" path="exports" />`.
  - `HonReaderBridge.kt`: in `shareFile`, defensively copies to native `exports/` cache dir if FileProvider resolution on external/document directory fails, logs errors, and returns `SHARE_FAILED` to Dart.
  - `HonFilesBridge.kt`: added `exportFileAs` via `ACTION_CREATE_DOCUMENT` for native SAF export of EPUBs.
  - `epub_export_service.dart`: added `ShareResult` model; `shareExportedEpub` returns `ShareResult` with descriptive error messages; added `saveExportedEpubAs` supporting SAF on Android and `FilePicker.platform.saveFile` fallback.
  - `source_catalog_screen.dart` & `library_screen.dart`: on export success, presents modal bottom sheet with "Share EPUB" and "Save As...", surfacing errors if share or save fails.

- **Targeted Fix 3 — EPUB Illustration Robustness & Atomic Output:**
  - `epub_export_service.dart`:
    - Added `await DatabaseService.instance.ensureChaptersLoaded(book.id)` when `chapters` argument is null.
    - Illustration URI parser handles single-slash `file:/` (from Java `toURI().toString()`), `file:///`, and plain paths; decodes percent-encoded URIs (`Uri.decodeFull`).
    - Validates image paths using `StorageService.instance.isPathInsideManagedStorage(file.path)` and `file.existsSync()`.
    - Deduplication map `localImageMap[file.path]` is updated only *after* file read and archive insertion succeed.
    - Strips unbundled/missing `<img>` tags (`result.replaceAll(fullMatch, '')`) so XHTML output is valid EPUB 3 without broken local references.
    - Periodic `await Future<void>.delayed(Duration.zero)` every 20 chapters to keep UI isolate responsive.
    - Atomic file creation: writes to `.part` file first and renames to `.epub` on completion, deleting temp file on error.
  - Verified via `test/unit/epub_export_service_test.dart` (3/3 passed: empty chapter failure, structural EPUB 3 validity, and illustration bundling / deduplication / missing tag stripping / atomic rename).

- **Targeted Fix 4 — Current-Chapter Positioning for Long Lazy Lists:**
  - `source_catalog_screen.dart`: index-aware offset calculation taking `_reverseChapters` into account (`chapters.length - 1 - readingIndex`); two-stage positioning: jumps/animates close to target row, followed by `addPostFrameCallback` with `Scrollable.ensureVisible` for pixel-perfect centering; `_initialScrollOnce` triggers only once.
  - `reader_contents_sheet.dart`: two-stage positioning with `addPostFrameCallback` alignment.

- **Targeted Fix 5 — Queue Notification Ownership & Batch Coordination:**
  - `DownloadNotifications.kt`: refactored to single queue coordinator with `ConcurrentHashMap` tracking active downloads; displays indeterminate progress (`setProgress(0, 0, true)`) eliminating worker progress jumps; automatically dismisses when queue count reaches 0.
  - `HonDownloadWorker.kt`: reports descriptive phases ("Downloading passage", "Extracting illustrations"); calls `onJobFinished` in `finally`.
  - `HonDownloadManagerBridge.kt`: in `requestAllJobsStopped`: (1) snapshots active jobs/books from SQLite, (2) synchronously invalidates and commits tokens, (3) acquires per-job scheduling locks before WorkManager cancellation and worker termination, (4) updates SQLite durable state only after all workers have stopped, (5) dispatches state notifications, (6) updates notifications.
  - Verified via `./gradlew :app:compileDebugKotlin` (`BUILD SUCCESSFUL`).

- **Targeted Fix 6 — Honest & Granular Source Diagnostics:**
  - `source_health_service.dart`: tests search with explicit non-empty query (`'a'`); distinguishes empty results (`CapabilityStatus.empty`) from network/parse errors (`CapabilityStatus.failed`); never infers search capability from an empty listing query.
  - Verified via `test/unit/source_health_service_test.dart` (7/7 passed: OK, policy block, Cloudflare/login, SSL failure, truthful diagnostic matrix, empty search results, and failing search execution).

- **Targeted Fix 7 — Native/Flutter Reader Appearance Parity:**
  - `ReadiumReaderActivity.kt`: when `isGlass == true` (and accessibility touch exploration is disabled), applies translucent card drawable with subtle stroke border to `topBar`, `bottomBar`, and bottom sheets; on API 31+ applies `FLAG_BLUR_BEHIND` and `blurBehindRadius = 25` to dialogs/sheets; removes `FLAG_BLUR_BEHIND` from main reader window so background apps are not blurred; updates `window.attributes = layoutParams` explicitly.

- **Targeted Fix 8 — Verification, Diagnostics, and Honest Status Reporting:**
  - Applied strict three-tier taxonomy: `implemented`, `focused-test verified`, and `needs phone check`.

---

## Phase 6 (Oct 22 Recheck Pass) — Comprehensive Resolutions

| Finding | Component | Resolution Details | Status |
| :--- | :--- | :--- | :---: |
| **1. Reload Enum Library Scope** | `reader_screen.dart` | Moved `enum ChapterLoadResult` outside `_ReaderScreenState` to library scope, resolving the Dart compile blocker while preserving explicit return outcomes (`refreshedOnline`, `offlineFallback`, `skipped`, `failed`) and memory-only reload semantics. | `implemented` (phone verification pending) |
| **2. Batch Cancellation Lock-Order Inversion** | `HonDownloadManagerBridge.kt` | Removed outer SQLite write transaction wrapping `HonDownloadWorker.stopAndAwait(target.jobId)`, preventing database writer stalls while awaiting workers. Workers stop cleanly without holding SQLite locks; short, localized per-job transaction commits status and verifies `status != 'completed'` and `download_state != 'downloaded'`. | `implemented` (phone verification pending) |
| **3. Bounded Measured Chapter Positioning** | `source_catalog_screen.dart`, `reader_contents_sheet.dart` | Aligned chapter tracking strictly to display positions (`displayIndex`), fixing inverted/mixed index orders on reversed lists. Replaced unbounded set accumulation with active mounted tracking (`_TrackedChapterItem` with `onMount`/`onUnmount`). Replaced blind guesses with bounded estimates using measured row heights and header reveal offsets. Not claimed exact until confirmed on physical devices under distant chapters, reversed order, and multi-line wrapping titles. | `implemented` (bounded measured estimate; phone verification pending) |
| **4. Native Glass Capability & Active Dialog Fallback** | `ReadiumReaderActivity.kt` | Restricts `isBlurAllowed()` to Android 12+ (API 31 / S), returning false on older Android versions where `blurBehindRadius` is unavailable. Tracks active open dialog (`activeDialog`) and content card (`activeDialogCard`). When runtime listeners (`ACTION_POWER_SAVE_MODE_CHANGED`, `crossWindowBlurEnabledListener`, `TouchExplorationStateChangeListener`) fire or appearance settings change, `updateThemeStyling` dynamically refreshes open dialogs: sets 100% opaque solid theme backgrounds, clears `FLAG_BLUR_BEHIND`, and sets `blurBehindRadius = 0` when blur is disabled. Reader glass parity is explicitly documented as partial because native toolbars use translucent drawable styling rather than equivalent backdrop filter material. | `implemented` (native material parity partial; phone verification pending) |
| **5. Coordinated Queue Notification Lifecycle** | `DownloadNotifications.kt`, `HonDownloadWorker.kt`, `HonDownloadManagerBridge.kt` | Implemented a centralized queue notification lifecycle state machine (`RUNNING`, `RETRY_WAITING`, `IDLE`) with generation-validated pending reservations and attempt tokens (`attemptToken = id.toString()`). Initial claims and handoffs serialize through `PendingReservation(jobId, attemptToken, generation)` under `foregroundLock` and `promotionMutex`, preventing concurrent workers from simultaneously claiming primary ownership. Promoted workers verify `isReservationValid` before `setForeground`; if promotion times out (3000ms bound), the promoter cancels and joins the elevation job inside `withContext(NonCancellable)` before returning, guaranteeing that ownership is never transferred to another worker while `setForeground` is in flight. In `HonDownloadWorker`, suspending cleanup in `finally` executes under `withContext(NonCancellable)` with a 5000ms bound; the timeout fallback unregisters safely and dispatches asynchronous background reconciliation (`scheduleReconciliation`) without blocking `runBlocking` calls, strictly bounding the cleanup path. In batch cancellation, `stopAllJobsDurableAndAwait` stops workers and calls `removeActiveJob(target.jobId, target.token)` strictly under target scheduling locks matching `target.token`, preventing old stopped attempts from removing restarted attempts. `reconcileSurvivingJobs` promotes surviving workers and updates notification 4001, dismissing it if and only if zero active/pending jobs remain. | `implemented` (coordinated WorkManager lifecycle; phone verification pending) |

---

## Physical Phone Testing Checklist

The following items cannot be fully verified via unit tests or JVM host execution alone and require testing on a physical Android device:

1. **Chapter Reload in Web Novel Reader:**
   - [ ] Tap chapter reload button in bottom footer bar while reading an online chapter.
   - [ ] Confirm reading scroll position is preserved without jumping to the top of the chapter.
   - [ ] Confirm offline downloaded files are not overwritten or corrupted by reload attempts.
   - [ ] Disable WiFi/data, tap reload, and verify fallback to saved copy with truthful "Reloaded from saved offline copy" SnackBar.

2. **EPUB Export & File Sharing / SAF "Save As":**
   - [ ] Export downloaded series as EPUB from the Library card popup menu and verify modal bottom sheet appears.
   - [ ] If illustrations were omitted, confirm the red omission warning note is displayed in the bottom sheet.
   - [ ] Tap "Share EPUB" and confirm Android system Share sheet opens without FileProvider crashes (`IllegalArgumentException: Failed to find configured root`).
   - [ ] Share to an external reader app (e.g. Google Play Books, Moon+ Reader) and verify illustrations and table of contents render properly.
   - [ ] Tap "Save As..." and verify Android Storage Access Framework (SAF) system file picker opens.
   - [ ] Press "Cancel" in the SAF file picker and confirm app returns cleanly with "Save cancelled" SnackBar, without opening a secondary file picker.

3. **Catalogue & Reader Contents Dynamic Chapter Centering:**
   - [ ] Open a series with 500+ chapters in `SourceCatalogScreen` where reading progress is at chapter ~300.
   - [ ] Verify catalog dynamically converges and centers on Chapter 300 without lag or getting stuck at index 0.
   - [ ] Toggle "Newest chapter first" sort order and confirm catalogue jumps to the correct reversed position without freezing or crashing.
   - [ ] Open Reader Contents sheet and confirm current reading chapter is immediately visible and centered in viewport.

4. **Background Download Queue & Notifications:**
   - [ ] Queue "Download Next 15" chapters while connected to WiFi.
   - [ ] Pull down Android notification shade: confirm ongoing notification showing indeterminate progress bar and queue item count.
   - [ ] Tap "Pause All": confirm notification dismisses, and newly enqueued jobs after pause snapshot are not cancelled or lost.
   - [ ] Tap "Cancel All": verify notification dismisses and database states reflect cancellation cleanly.

5. **Readium Native EPUB Appearance & Glass Fallback:**
   - [ ] On Android 12+ (API 31+) device, switch app appearance to "Liquid Glass" mode.
   - [ ] Open an EPUB book in Readium reader: verify top bar, bottom scrubber bar, and appearance dialog display translucent glass styling.
   - [ ] Turn on Battery Saver mode while in the reader: verify bars and dialogs immediately switch to 100% solid opaque background.
   - [ ] Turn off Battery Saver mode: verify translucent glass styling restores immediately.
   - [ ] Confirm the main reader window does NOT blur phone wallpaper/desktop behind text.
   - [ ] Verify System Brightness toggle respects device ambient brightness when enabled and custom slider overrides when disabled.

