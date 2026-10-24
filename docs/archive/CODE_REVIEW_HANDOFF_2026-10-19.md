# Hon — code review and handoff

Date: 19 October 2026

## Scope and conclusion

Reviewed the current local source and the two supplied Antigravity progress reports. This review did not change application code or run additional tests/builds. Findings below come from source inspection; they are not new device reproductions.

The checkout contains substantial uncommitted and untracked work, including newer Antigravity changes. Preserve it before continuing. Review XML exports and completion documents are context; the current application source is the implementation evidence.

**The claim that all implementation is complete and only phone testing remains is not supported by the current code.** Several useful improvements are present, but there are still data-integrity defects and incomplete reader integration.

User priorities: functionality first, UI afterward, testing last. Keep automated verification focused and leave broad phone testing to the user. Do not spend time repeatedly running full suites or sweeping every source website.

## Priority findings

### 1. P1: Chapter reconciliation can associate old downloaded text with a different chapter

Evidence: `lib/core/updates/chapter_update_service.dart:164–200`.

After matching source IDs and normalized titles, the third pass matches solely by chapter index. Its comment promises title similarity, but the code performs no such check. The subsequent `matchedOld.copyWith(...)` changes title and URL while retaining the old local file, download state, and identity.

If an upstream source replaces a chapter at the same position, Hon can display old content under the replacement chapter's title and fail to recognize it as new. The title pass also selects the first matching title without rejecting ambiguous duplicate titles.

Required change: use stable upstream identities first and only conservative, unique fallback matches. Never transfer downloaded content solely because positions match. For a genuine identity repair, retain the local ID used by progress/bookmarks while recording the new upstream identity. Preserve uncertain old downloads without relabeling them as confirmed matches.

Final focused check: same-position replacement and duplicate chapter titles must not inherit unrelated downloaded files.

### 2. P1: Backup restoration leaves offline image references pointing at old locations

Evidence:

- `android/app/src/main/kotlin/com/hon/reader/hon/OfflineChapterImages.kt:132` writes absolute `file:` URIs into chapter HTML.
- `lib/core/backup/backup_service.dart:450–523` extracts into a new restore directory and relocates book/chapter metadata paths, but does not relocate image references inside the HTML.

The backup can contain the images while restored chapters still reference the original image directory. A same-device restore can conceal this because the original files remain available.

Required change: introduce portable managed image references, or safely rewrite validated local image references during restoration. Keep archive path validation and checksum checks intact. Handle existing absolute-URI chapter files as a migration case.

Final focused check: restore into a different root with the original files unavailable and confirm an offline illustrated chapter resolves its images.

### 3. P1: Collection names are not restored into the new canonical database tables

Evidence:

- `lib/core/database/database_service.dart:273`: snapshot export does not include collection-table records.
- `lib/core/backup/backup_service.dart:157`: restoring `hon_collections_v1` writes names to SharedPreferences.
- `lib/core/database/database_service.dart:98`: `reloadPreferences()` reloads preferences and notifies; it does not reload/import SQL collections. The `collections` getter uses `_collections`.

After the v3 migration has already run, restored legacy preferences do not repopulate the canonical SQL collection store. Memberships can therefore reference missing collection names. SQL-only changes also need a reliable export path.

Required change: export, validate, and import collection records and their memberships through the canonical database, transactionally where possible. Explicitly convert legacy preference-format backups during import; do not rely on a one-time startup migration rerunning.

Final focused check: restore named collections into an already initialized v3 database, then restart and verify names and memberships persist.

### 4. P1/P2: Android EPUB does not receive the newly claimed reader features

Evidence:

- `lib/features/reader/presentation/reader_navigator.dart:52`: Android EPUB opening reads global `hon_reader_preferences_v1`; it does not merge the new per-book database overrides.
- `lib/core/native/readium_reader_service.dart:109`: native bookmark toggling passes chapter index and label without a precise locator.
- `android/app/src/main/kotlin/com/hon/reader/hon/ReadiumReaderActivity.kt:890`: bookmark navigation uses `pageIndex` as a reading-order index and navigates to that resource, ignoring precise locator fields.
- The native selection callback around `ReadiumReaderActivity.kt:308–340` adds quote sharing, not the new highlight/note actions.

Required change: carry effective per-book preferences through the native bridge, save and restore Readium bookmark locators, and integrate native EPUB highlight/note creation and display. Account separately for the continuous EPUB path and fixed-layout restrictions. Until this is connected, describe the feature support per reader rather than claiming universal support.

Additional Flutter gap: `lib/features/reader/presentation/reader_screen.dart:458` captures a viewport anchor when saving a highlight. This is not the selected text's start/end range. Persisted highlight creation/listing also does not establish inline highlighted-text rendering. Store a stable selected range with text context and render it when the chapter is reopened.

Final focused check: one per-book setting, one bookmark midway through a chapter, and one saved highlight should survive reopening in each supported reader path.

### 5. P2: Source initialization can request the network before its host policy is ready

Evidence:

- `android/app/src/main/kotlin/com/hon/reader/hon/shosetsu/ShosetsuKotlinEngine.kt:125–147` executes the extension chunk before reading its returned `baseURL` into `policy.baseHost`.
- `SourceNetworkPolicy.kt` denies requests when there is no base host or matching explicit extra host.
- `ShosetsuLuaHost.kt:167` applies that policy to requests.

Extensions that fetch filter data during construction can fail before their returned table declares the host. Multi-host sources also require appropriate explicit permissions. This is a concrete compatibility gap, but does not prove it is the cause of every source failure reported on the phone.

Required change: establish source network capabilities from validated installation metadata before script execution, including declared bootstrap hosts where needed. Keep redirect checks and bounded execution. Show actionable source-specific errors; do not disable the policy globally to make sources appear to work.

Final focused check: cover both a normal extension and one that performs an authorized bootstrap request, plus a blocked unauthorized redirect.

### 6. P2: Offline image validation and re-encoding disagree about supported formats

Evidence: `android/app/src/main/kotlin/com/hon/reader/hon/OfflineChapterImages.kt`.

The MIME fallback near line 28 accepts any `image/*` header, including SVG or bytes mislabeled by the server. Downscaling can encode non-JPEG images as PNG while subsequent naming/type decisions still use the original format. A width-only scaling limit also does not bound the decoded pixel count of a very tall image.

Required change: use an explicit supported-format policy and validate decoded images. Have the transform return bytes together with their actual output MIME type and extension. Bound pixel count as well as encoded size. Preserve graceful chapter download behavior when an individual illustration fails.

Final focused check: mislabeled content, a resized WebP/GIF input, and an oversized image should produce a supported image or a controlled omission.

## Completion claims that need qualification

- **Bundled catalog upgrades:** `lib/core/sources/bundled_source_catalog.dart:32` still exits using a fixed seeded marker. The current code does not establish automatic version-aware catalog refresh on app upgrades. Design refresh separately from reinstall so intentionally removed sources are not silently restored.
- **Startup self-check:** the native `selfCheck()` executes a simple `return 42` check. This does not establish the broader table/metatable compatibility checks described in the report.
- **Native binary compatibility:** updating the SQLite dependency does not verify every native library packaged in the app. Inspect the final APK's native libraries at packaging time, including reader/PDF dependencies.
- **Testing:** the reported test totals are supplied results, not fresh verification by this review. Passing tests only establish their covered cases; the integration gaps above remain.
- **APK handover:** the named release handover in `build/releases` remains 1.1.1. This review has not established a freshly validated release containing all current changes. Do not confuse a newer source tree or debug build with the APK installed on the user's phone.

## Improvements present in the source

These should be preserved while resolving the findings:

- LuaJ retention rules and native engine failure reporting.
- Lazy per-book chapter loading and asynchronous full chapter export.
- Schema additions for collections, updates, highlights, reader overrides, and bookmark locators.
- Encrypted native source settings and improved source request controls.
- Bounded download concurrency and foreground download notifications.
- File-based offline image storage and graceful handling of individual image failures.
- Glass appearance choices and accessibility-related fallbacks.

Presence of tables or controls does not demonstrate that all readers, backup paths, and native bridges use them correctly.

## Recommended remaining work order

1. Protect downloaded chapter identity and fix both backup/restore defects.
2. Finish source initialization/installation compatibility and clear error reporting. Distinguish unavailable websites from app engine failures.
3. Complete per-book settings, bookmark locators, and highlights across reader paths; then correct offline image handling.
4. Make catalog upgrades explicit and reconcile completion documentation with actual support.
5. Finish UI polish: minimal glass by default, optional stronger glass, readable contrast, and bounded blur regions. Preserve the downloaded reader as the shared interaction reference.
6. At the end, run a small set of regressions tied to the changed paths and produce one optimized APK with the existing update-compatible signing identity. Give the user a short phone checklist and accurate implemented/unverified status.

Do not uninstall the user's app or erase reading data as a shortcut. Avoid claiming all functionality is finished until the integration items above are implemented.

## Further optimizations worth considering after correctness

- Bound the lazy chapter cache: loading per book reduces startup cost, but retaining every visited book indefinitely can still grow memory use.
- Add reference-aware cleanup for shared offline images so deletion and restore do not accumulate orphan files or remove images still in use.
- Keep glass blur clipped to small UI regions and avoid rebuilding reader content for unrelated download/status updates.
- Measure performance in an optimized build before attributing all jank to debug mode or adding speculative caching.

These are follow-up opportunities, not additional defects reproduced in this review.
