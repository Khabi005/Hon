# Architecture & Implementation Decisions (DECISIONS.md)

## ADR-001: UI Framework & Design Language
- **Decision:** Flutter with custom Apple Books (iOS 18) design system components.
- **Rationale:** 
  - Standard Material 3 or Cupertino widgets diverge visibly from iOS 18 Apple Books (e.g. floating translucent bottom capsule dock, Aa popup menu stack, TOC sheet with segmented tabs, gradient continue cards).
  - Custom Flutter components provide complete visual control, pixel precision, Newsreader typography, and 6 reader themes (Original, Quiet, Paper, Bold, Calm, Focus).

## ADR-002: Navigation and Tab Ordering
- **Decision:** Tab order: `Home`, `Library`, `Browse`, `Search`, `Downloads`.
- **Rationale:** 
  - Aligns with iOS 18 Apple Books and user specification.
  - Floating frosted capsule dock with active pill indicator.

## ADR-003: Local Persistence & Storage Architecture
- **Current Baseline (Phase 0A):** SharedPreferences JSON collections + file-backed storage (`publications`, `covers`, `chapters`, `staging`).
  - Chapter records, progress, download jobs, and library entries serialized.
  - No synthetic demo books or fabricated progress automatically seeded.
  - Genuinely empty when empty.
- **Target Architecture (Phase 0D Gate):** Drift (SQLite) running on a background isolate with versioned migrations, atomic transactions, and recovery.

## ADR-004: Reader Engine Strategy
- **Android Native Platform Boundary (Readium Toolkit 3.1.1):**
  - Readium Kotlin dependencies integrated: `readium-shared`, `readium-streamer`, `readium-navigator` (3.1.1) with Java 8+ desugaring (`desugar_jdk_libs:2.1.4`).
  - Native reader hosted in `ReadiumReaderActivity` wrapping `EpubNavigatorFragment`.
  - Fragment factory installed strictly before `super.onCreate(savedInstanceState)` using declared resource ID `R.id.readium_fragment_container` to ensure crash-free Android process and configuration restoration.
  - Appearance controls (`Aa` dialog: font size, theme, paged vs continuous scroll) persisted in `hon_reader_preferences` SharedPreferences.
  - Nested TOC flattened with depth indentation (`flattenToc`) to expose sub-chapters and volumes.
  - Multi-book persistence isolation: per-book pending progress map with 500ms debounce and 3s max periodic flush during continuous scroll; instant synchronous database flush on reader close / Back.
  - Request/session tracking (`requestId`) connects `onReaderReady` and `onReaderError` with explicit UI error dialog and Dart fallback option.
  - Note: Compiles cleanly into Android debug APK via Gradle; on-device/emulator rendering verification remains explicitly marked Pending until physical device/emulator is connected.
- **Desktop Preview Reader (Dart):**
  - HTML DOM parser with UTF-8 decoding (`utf8.decode`), italic/bold span preservation, Apple Books Aa floating menu, real TOC modal sheet (`Chapters`, `Bookmarks`, `Highlights`), chapter navigation, dual layout modes (vertical scroll and horizontal swipe), and durable reading location restoration via `ReaderNavigator`.
  - Normalized Readium `href` matched against `EpubChapterItem.contentHref` for seamless fallback.
- **PDF Reader:**
  - Platform-capability checked. Explicit friendly notice on unsupported Linux desktop; single-instance `pdfx` integration on Android with page clamping, zoom, bookmarks, and appearance persistence.

## ADR-005: Source Runtime & Extensibility
- **Current Baseline (Phase 0A Prototype):**
  - `SourceRegistry` supporting `Sources` and `Extensions` UI shells (no Migrate).
  - Note: Catalogue lists and extension "installs" are prototypes pending the Phase 0C upstream Lua engine. Fabricated updates in Downloads tab are disabled in standard operation.
- **Target Architecture (Phase 0C Gate):** Upstream Shosetsu Lua runtime compatibility, repository index contract, and live extension sandboxing.

## ADR-006: Chapter Downloads & Library Independence
- **Decision:** Explicit, decoupled state machines for Library Entry vs Download Jobs.
- **Prompt:** When downloading chapters of a novel outside the library, prompt:
  - Title: "Add to Library?"
  - Body: "Add \"{novel title}\" to your library to find it easily and check for new chapters."
  - Actions: "Add to Library" · "Not Now"
- **Rules:**
  - Either action proceeds with download.
  - "Not Now" suppresses prompt for that novel for the session.
  - Downloads are viewable in Downloads tab and Reading History regardless of library presence.
  - Deleting from library does not delete downloaded files; deleting downloads does not remove library entry.
  - Downloads screen includes `Downloads` and `Updates` mini-tabs.

## ADR-007: Prototype vs Production Feature Boundaries
- **Decision:** Do not present mock/prototype data as live, working services.
- **Rules:**
  - When background services (e.g., chapter update check, source scraping) do not exist yet, display honest empty states or explicit prototype banners.
  - Do not synthesize mock updates ("Today", "Yesterday") to populate screens.
  - Label platform stubs accurately as interfaces rather than claiming engine completion.

## ADR-008: Native Android Reader UI Strategy
- **Decision:** Separate functional reader ergonomics from the cosmetic Apple Books visual redesign pass, and explicitly track native Android Kotlin reader controls separately from Flutter reader widgets.
- **Rationale & Rules:**
  - The Android EPUB reader is rendered natively via Readium (`ReadiumReaderActivity` hosting `EpubNavigatorFragment`). Polishing Flutter's reader widgets (`reader_controls.dart`, `reader_settings_sheet.dart`) does not affect the native Android EPUB reading screen.
  - Reading ergonomics fixes are applied immediately to native Kotlin:
    1. Framing: Top and bottom toolbars are placed in a non-overlapping vertical `LinearLayout` with the fragment container given `weight = 1.0f` and `WindowInsetsCompat` padding. When controls are visible, chapter titles and bottom text are never obscured.
    2. System Bar Contrast: In light and sepia reading modes, `WindowInsetsControllerCompat.isAppearanceLightStatusBars` dynamically sets dark status-bar icons so indicators remain legible against light page backgrounds.
    3. Typography & Spacing: Publisher CSS margins and text alignment (e.g., `margin: 0 0 30pt;`) are preserved by default rather than globally stripped, respecting intentional publisher formatting.
  - The visual redesign of native Kotlin reader controls is tracked as a dedicated milestone: **Phase 0-ReaderUI: Native Android Reader Apple Books Design Pass (Classic Apple Books aesthetic + modern paragraph formatting & typography)**.
    - References approved: Classic Apple Books overall aesthetic (clean bottom toolbar, classic typography sheets, subtle TOC / bookmark ribbon) combined with modern Apple Books paragraph formatting & themes (from user screenshots).

## ADR-009: Library Removal & Deletion Semantics
- **Decision:** Provide two distinct, explicit actions for removing books from the Library screen:
  1. **"Remove from Library"**: Sets `isInLibrary = false`. Preserves the book record, reading progress, and all downloaded chapter/file data on disk. Available with quick Undo option.
  2. **"Remove from Library and Delete"**: Requires explicit user confirmation dialog. Permanently deletes the local EPUB/PDF file and local cover from disk, purges database entries, and cleans up associated download jobs.
- **Reading Minutes Tracking**: Foreground reader sessions in Readium (`ReadiumReaderActivity`), `PdfReaderScreen`, and `ReaderScreen` accumulate active seconds and dynamically increment daily reading minutes in `DatabaseService` (`addReadingTime`).

## ADR-010: Source Network Policy and Host Allowlist
- **Decision:** Restrict Shosetsu Lua extension HTTP requests to the extension's declared `baseURL` registrable domain (and subdomains) plus an explicit per-source host allowlist. All HTTP redirects are strictly re-checked.
- **Rationale:** 
  - Prevents untrusted third-party extension scripts from scanning local networks (e.g., `192.168.x.x`, `10.x.x.x`, `localhost`) or leaking user session tokens/cookies to arbitrary external servers.
  - OkHttp network interceptors verify the destination host for the initial request and every subsequent redirect hop.
  - When blocked, a descriptive error naming the blocked host is raised (`Network request to '...' blocked by source network policy.`).
- **What this may break:**
  - Extensions that fetch chapter content, novel metadata, or CDN images hosted on distinct domains different from their declared `baseURL` (e.g. image CDNs like `cdn.example.com`, Cloudflare image domains, or external API gateways).
- **How a user can add a host:**
  - Navigate to **Browse** > tap the source's overflow menu / **Controls & Preferences** (or **Settings** > **Sources**).
  - Scroll down to the **Network Policy & Allowed Hosts** section.
  - Tap **Add Host**, enter the hostname or domain (e.g., `images.contentcdn.com`), and tap **Add**.
  - Tap **Save** to persist the updated host allowlist.

## ADR-011: Root CA Trust & Intermediate Bundling (ISRG Root YR)
- **Decision:** Embed both self-signed `ISRG Root YR` root anchor and cross-signed certificate into Hon's custom TrustManager bundle, hardcoded via code PEM constants in `SourceHttpClient.kt` and bundled as resource CRT.
- **Rationale:** 
  - Sources like 1stKissNovel use TLS certificates issued by `YR2`, chaining to Let's Encrypt's 2025 root `Root YR`. Older Android systems lack this root in their system trust store.
  - Supplying only the cross-signed cert failed Android PKIX validator because it lacked a self-signed trust anchor.
  - Hardcoded code constants guarantee availability even if APK resource stripping occurs during release builds.

## ADR-012: WorkManager vs Flutter Lifecycle in Downloads & Update Checks
- **Decision:** Treat WorkManager as the durable out-of-process authority for download jobs and periodic update checks.
- **Rationale:**
  - When Flutter restarts or recovers downloads, active running jobs retain `DownloadStatus.running` and use `ExistingWorkPolicy.KEEP` so in-flight WorkManager workers are not killed and restarted from 0%.
  - Background update checks run via `HonUpdateCheckWorker` (CoroutineWorker) with configurable periodic constraints (clamped $\ge 1\text{h}$, Wi-Fi only, battery not low), using an abstract `UpdateCheckDatabase` interface that operates directly on SQLite without Flutter engine instantiation.
  - Chapter reconciliation is strictly additive: existing chapter IDs are preserved with their local download states, and brand new upstream chapters are inserted with `notDownloaded`.

## ADR-013: Reader Preference Isolation (Global Defaults vs Book Overrides)
- **Decision:** Every preference write operation explicitly carries its destination scope (global vs `bookId`), captured immutably at invocation time.
- **Rationale:**
  - Reading a mutable `_activeBookId` at execution time caused asynchronous preference writes to bleed book-specific styles into global preferences.
  - Per-book overrides are strictly stored in `book_reader_settings_table`.
  - "Reset to Defaults" clears the book override record from SQLite and reverts the active reader session to global defaults without writing book settings to global preferences.

## ADR-014: Download Queue Notification Lifecycle & Aggregate Foreground Ownership
- **Decision:** Coordinate download queue notifications through a centralized lifecycle state machine (`RUNNING`, `RETRY_WAITING`, `IDLE`) with atomic primary worker ownership, rather than uncoordinated per-worker notification churn.
- **Lifecycle & Architecture:**
  - **WorkManager Architecture:** WorkManager manages execution via `SystemForegroundService`. When concurrent download workers start, the first worker is atomically designated the **Primary Foreground Owner** (`primaryWorkerJobId`), establishing the single foreground notification under ID `4001`.
  - **Concurrent State Aggregation:** Additional concurrent workers register their active chapter titles and sub-phases ("Downloading passage", "Fetching illustration 2/5") into a thread-safe `activeJobs` registry. The notification displays active task descriptions (or `N downloading simultaneously`) with a durable SQLite-backed queue subtext (`N in queue`).
  - **Inter-Worker & Completion Lifecycle:** When a worker finishes a chapter:
    - It unregisters from `activeJobs`.
    - If it was the primary owner, ownership is transferred atomically to the next active worker in the registry.
    - If all active workers have finished and the SQLite queue is empty, the notification is immediately cancelled.
  - **Retry & Backoff Transitions:** When all active workers halt due to rate-limiting (HTTP 429) and remaining jobs enter `retryWaiting`:
    - The notification transitions from an ongoing foreground state (`setOngoing(true)` with indeterminate spinner) to a dismissable status notification (`setOngoing(false)` without spinner): *"Hon · Downloads waiting to retry — Waiting for source cooldown (N chapters remaining)"*.
  - **Explicit Cancellation & Pause:** When pause or cancel all is requested via notification action or UI, `DownloadNotifications.cancelAll(context)` cancels notification `4001` immediately.
  - **Background Elevation Fallback Boundary:** If `setForeground` fails (e.g. Android 12+ `ForegroundServiceStartNotAllowedException` when triggered from deep background without exemption), it is caught and logged. The task continues executing under standard WorkManager background constraints rather than crashing; posting an informational notification in this state does *not* grant foreground service priority.

## ADR-015: Native Reader Glass Capability, Runtime Observers & Solid Fallback
- **Decision:** Restrict native glass mode to Android 12+ (API 31+) with hardware blur support; enforce 100% opaque solid themes on older Android releases or when performance/accessibility constraints are active; dynamically update open dialogs on runtime system events.
- **Capability & Fallback Policy:**
  - **Platform Requirement:** Native dialog `blurBehindRadius` requires Android 12+ (API 31 / S). On Android 8.0–11 (APIs 26–30), `isBlurAllowed()` strictly returns `false`, preventing transparent windows without blur.
  - **System Constraints:** `isBlurAllowed()` returns `false` whenever Battery Saver mode is enabled (`PowerManager.isPowerSaveMode`), Accessibility Touch Exploration is active (`AccessibilityManager.isTouchExplorationEnabled`), or cross-window blur is disabled (`windowManager.isCrossWindowBlurEnabled`).
  - **Active Dialog Material Tracking:** `ReadiumReaderActivity` tracks currently open dialogs (`activeDialog`) and their content card (`activeDialogCard`). When runtime observers (`ACTION_POWER_SAVE_MODE_CHANGED`, `crossWindowBlurEnabledListener`, `TouchExplorationStateChangeListener`) fire or appearance settings change:
    - If blur is allowed: sets translucent background + border stroke, enables `FLAG_BLUR_BEHIND`, and sets `blurBehindRadius = 25`.
    - If blur is disallowed: immediately updates card background to 100% opaque solid theme color, explicitly clears `FLAG_BLUR_BEHIND`, and sets `blurBehindRadius = 0`.
  - **Parity Status:** Native reader bars utilize translucent drawable styling rather than Flutter-like backdrop material; reader glass parity is explicitly documented as partial pending deeper native shader/backdrop rendering.


