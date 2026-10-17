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
