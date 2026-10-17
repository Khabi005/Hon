# Hon — Project Implementation Progress & Requirements Matrix

## Truthful Requirements & Status Matrix

| Subsystem | Feature | Implemented | Unit Tested | Android Build | Device / Runtime Verified | Real State & Notes |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **Android Native (Readium)** | Readium Toolkit 3.1.1 & Activity | ✅ | ✅ | ✅ | ⏳ **Pending** | `ReadiumReaderActivity` hosting `EpubNavigatorFragment` with desugared Java 8+ APIs; runtime verification pending device/emulator availability. |
| **Android Native (Readium)** | Whole-Book Progression | ✅ | ✅ | ✅ | ⏳ **Pending** | Shared `computeTotalProgression` across live reading, `finish()`, and `onDestroy()`; uses `loc.locations.totalProgression` with fallback to `(resourceIndex + chapterProgression) / readingOrder.size`. |
| **Android Native (Readium)** | Native TOC & Navigation | ✅ | ✅ | ✅ | ⏳ **Pending** | Dedicated TOC dialog with recursive link traversal and indentation (`flattenToc`) for volumes/parts; bottom bar `❮ Prev` and `Next ❯` buttons. |
| **Android Native (Readium)** | Native Appearance Controls | ✅ | ✅ | ✅ | ⏳ **Pending** | `Aa` modal dialog with font size step controls, theme switcher (Dark, Sepia, Light), and layout mode (Paged reflow vs Continuous scroll); persisted to `hon_reader_preferences` SharedPreferences. |
| Subsystem | Feature | Implemented | Unit Tested | Android Build | Device / Runtime Verified | Real State & Notes |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **Android Native (Readium)** | Readium Toolkit 3.1.1 & Activity | ✅ | ✅ | ✅ | ⏳ **Pending** | `ReadiumReaderActivity` hosting `EpubNavigatorFragment` with desugared Java 8+ APIs; runtime verification pending device/emulator availability. |
| **Android Native (Readium)** | Whole-Book Progression | ✅ | ✅ | ✅ | ⏳ **Pending** | Shared `computeTotalProgression` across live reading, `finish()`, and `onDestroy()`; uses `loc.locations.totalProgression` with fallback to `(resourceIndex + chapterProgression) / readingOrder.size`. |
| **Android Native (Readium)** | Native TOC & Navigation | ✅ | ✅ | ✅ | ⏳ **Pending** | Dedicated TOC dialog with recursive link traversal and indentation (`flattenToc`) for volumes/parts; bottom bar `❮ Prev` and `Next ❯` buttons. |
| **Android Native (Readium)** | Native Appearance Controls | ✅ | ✅ | ✅ | ⏳ **Pending** | `Aa` modal dialog with font size step controls, theme switcher (Dark, Sepia, Light), and layout mode (Paged reflow vs Continuous scroll); persisted to `hon_reader_preferences` SharedPreferences. |
| **Android Native (Readium)** | Explicit Error Handling & Lifecycle | ✅ | ✅ | ✅ | ⏳ **Pending** | Connected `onReaderReady` and `onReaderError` with structured request tracking (`requestId`); explicit timeout error (never inferring readiness from elapsed time); late error reporting via `HonApp` SnackBar and `lastErrorNotifier`. |
| **Android Native (Readium)** | Non-Blocking Async Loading & Restoration | ✅ | ✅ | ✅ | ⏳ **Pending** | Asynchronous opening via `lifecycleScope.launch(Dispatchers.IO)` on normal launch (`super.onCreate(null)` with loading spinner); configuration change restoration utilizes in-memory `PublicationRepository` to install `fragmentFactory` before `super.onCreate(savedInstanceState)` with zero blocking. |
| **Persistence / Bridge** | Multi-Book Bounded Write Queue | ✅ | ✅ | ✅ | ✅ (Linux) | `_pendingByBook` isolation; `onPause()` dispatches `onReaderPaused` for immediate disk flush; `onReaderClosed` with null/empty locator preserves existing progress untouched (no 0% reset); failed writes remain pending with errors reported to `persistenceErrorNotifier`. |
| **Persistence / Bridge** | Locator Format Versioning & Href Match | ✅ | ✅ | ✅ | ✅ (Linux) | `locatorVersion` tag (`readium-v1` vs `dart-dom-v1`); normalized Readium href matched against `EpubChapterItem.contentHref` for seamless fallback. |
| **Desktop Preview (Dart)** | Chapter Swipe Mode | ✅ | ✅ | ✅ | ✅ (Linux) | Accurately labeled "Swipe"; handles horizontal chapter swiping with post-frame scroll position restoration. |
| **Desktop Preview (Dart)** | Completion Calculation | ✅ | ✅ | ✅ | ✅ (Linux) | Mathematical progress: combined chapter index and intra-chapter scroll fraction; manual "Finished" status kept strictly independent. |
| **Reader (PDF)** | Pinch-to-Zoom & Dual Mode | ✅ | ✅ | ✅ | ✅ (Linux) | Async open validation, onDocumentError handlers, initialPage clamping, color filter & mode persistence. |
| **Reader (PDF)** | Error Card & Controls Safety | ✅ | ✅ | ✅ | ✅ (Linux) | Controls disabled in error/loading/unsupported state; error card removes library membership without deleting book records. |
| **Home Screen** | Shelf & Reading Goals | ✅ | ✅ | ✅ | ✅ (Linux) | Clean empty shelf, honest continue reading, iOS 18 Reading Goals arc gauge modal sheet, Books Read This Year. |
| **Library Screen** | Empty State & Sorting | ✅ | ✅ | ✅ | ✅ (Linux) | Truly empty state with Import button; title (A-Z/Z-A), recently read, and progress sorting; chapter count badge. |
| **Browse (Sources)** | Catalogue Integrity | ✅ | ✅ | ✅ | ✅ (Linux) | Mock catalogues disabled (`enableDemoCatalogues = false`); clean empty state until live Lua sources in Phase 0C. |
| **Downloads & Updates** | Integrity & Prompt Sequence | ✅ | ✅ | ✅ | ✅ (Linux) | Synthetic updates removed; Section 5 Add-to-Library prompt queues downloads durably before prompting. |

---

## Detailed Evidence & Verification Log

### 1. Host Verification (Linux VM)
- **Static Analysis:** `flutter analyze` completed with **0 issues found**.
- **Automated Tests:** `flutter test` completed with **26 passed, 0 failed**:
  - `test/unit/readium_reader_service_test.dart`: Locator synchronization, multi-book persistence isolation, instant synchronous flush on `onReaderClosed`, bounded periodic flush, onReaderPaused immediate flush, null-locator progress preservation, onReaderError handling, and format versioning.
  - `test/unit/pdf_reader_test.dart`: PDF page clamping, bookmark CRUD, appearance persistence, library membership removal, and mathematical completion.
  - `test/unit/epub_parser_test.dart`: UTF-8 decoding and HTML DOM styling preservation.
  - `test/unit/library_prompt_and_storage_test.dart`: Section 5 prompt flow and storage invariants.
  - `test/widget_test.dart`: Navigation shell, tab order, and capsule dock.

### 2. Android Build Compilation
- **Gradle Task:** `./gradlew assembleDebug`
- **Result:** `BUILD SUCCESSFUL in 15s` (236 actionable tasks).
- **Target APK:** `build/app/outputs/flutter-apk/app-debug.apk`
- **Native Components Included:**
  - `org.readium.kotlin-toolkit:readium-shared:3.1.1`
  - `org.readium.kotlin-toolkit:readium-streamer:3.1.1`
  - `org.readium.kotlin-toolkit:readium-navigator:3.1.1`
  - `com.android.tools:desugar_jdk_libs:2.1.4`
  - `ReadiumReaderActivity.kt` registered in `AndroidManifest.xml`

### 3. Device / Runtime Verification Status
- **Desktop Linux:** Verified functional for Dart reader, UI navigation, and PDF fallback notice.
- **Android Runtime:** **Pending**. No physical Android hardware or running Android emulator (`adb devices`) is connected in this container environment. Runtime validation of actual on-screen Readium rendering, touch gestures, and process recreation will be performed as soon as an Android device/emulator is attached.
