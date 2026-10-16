# Architecture & Implementation Decisions (DECISIONS.md)

## ADR-001: UI Framework & Design Language
- **Decision:** Flutter with custom Apple Books (iOS 18) design system components.
- **Rationale:** 
  - Standard Material 3 or Cupertino widgets diverge visibly from iOS 18 Apple Books (e.g. translucent frosted bottom tab bars, gradient hero "Continue" cards, sheet headers, theme picker cards).
  - Custom Flutter components provide complete visual control, pixel precision, custom typography, and multi-theme adaptability without platform view layout compromises for the primary shell.

## ADR-002: State Management & Architecture
- **Decision:** Riverpod (Flutter Riverpod with code generation / StateNotifier / AsyncNotifier).
- **Rationale:** Compile-safe dependency injection, testable architecture, clean separation of presentation, business logic, and repositories. Prevents monolithic global controllers.

## ADR-003: Local Persistence & Storage
- **Decision:** Drift (SQLite) running on a background isolate + file-backed storage for publications & chapters.
- **Rationale:** 
  - Drift provides robust relational querying, type-safe migrations, reactive query streams, and out-of-the-box isolate execution.
  - Large publication files (EPUB, PDF, cached chapter HTML/images) reside in app-private storage, referenced by URI/path in the database.
  - Schema versions are tracked with explicit migrations.

## ADR-004: Reader Engine Strategy
- **Decision:** Dual-engine reader architecture:
  - **EPUB & Web Novel Reader:** Native Flutter rendering pipeline with HTML DOM parsing / pagination / continuous scroll, font & theme controls, custom typography presets (Original, Quiet, Paper, Bold, Calm, Focus), chapter transitions, and anchor-based locators (CFI / chapter + offset).
  - **PDF Reader:** PDF rendering integration using native canvas/pdfx with page caching, zoom/pan gestures, and page number restoration.
- **Rationale:** Allows unified theming, responsive gesture overlays, instant Flutter UI controls over the reader, reliable cross-device typography styling matching the iOS 18 reference screenshots, and resilient progress tracking.

## ADR-005: Source Runtime & Extensibility
- **Decision:** Bounded `NovelSource` contract with native/Dart runtime adapters and Shosetsu repository compatibility exploration.
- **Interface Contract:**
  - `browse(BrowseRequest)`
  - `search(SearchRequest)`
  - `getNovel(String novelId)`
  - `getChapters(String novelId)`
  - `getChapter(String chapterId)`
- **Rationale:** Decouples extension/scraping/fetching mechanics from UI and reader. Allows mock sources, HTTP/HTML scraping sources, and extension compatibility engines without altering database or reader logic.

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
