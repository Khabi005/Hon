# Hon — recheck of Antigravity's “all 12 resolved” update

## Latest recheck: subsequent “all eight implemented” report

**This section supersedes the status assessment below; the older review is retained as history.** Inspected the latest local implementation against the newly supplied report. No tests or builds were run. Antigravity reports 30 passing tests and a successful Kotlin compile; those are useful checks, but do not establish that every integration path is complete.

### Improvements confirmed

- Reload now reaches a forced fetch and retains the existing in-memory document when fetching/parsing fails.
- Export now hydrates chapters, recognizes `file:/` URIs, and has Share/Save As actions. FileProvider configuration now covers the export directory, and a cache-copy fallback exists.
- Image deduplication is recorded after successful insertion.
- Search diagnostics actually submit a nonempty query when the initial health check succeeds.
- Notification text aggregates active jobs and uses indeterminate progress instead of artificial transfer percentages.

### Remaining work, in priority order

1. **Reload can damage the saved offline version.** `reader_screen.dart:98` fetches raw passage HTML and directly overwrites the existing downloaded file before sanitization/parsing succeeds. It bypasses native illustration embedding, atomic replacement and the download job lock. This can replace local illustration URLs with online URLs, race a worker, or leave a truncated file after a failed write. Keep reload memory-only, or use the coordinated offline-download pipeline to replace the saved chapter. Preserve the old file until its replacement is fully prepared. Distinguish “using saved copy” from “refreshed online” when fallback occurs.

2. **Batch Pause/Cancel still races enqueue/resume.** `HonDownloadManagerBridge.requestAllJobsStopped` still unions the snapshot with all `schedulingLocks.keys`. It removes tokens before acquiring per-job locks, then releases those locks before a later blanket SQL update of every queued/running/retryWaiting job. Work enqueued after the snapshot can be marked paused/cancelled without being stopped, and replacement tokens can be affected outside the intended action. Serialize the batch boundary with scheduling, capture job ID plus attempt/generation, and update/cancel only that captured set under consistent coordination. Preserve newly enqueued/replaced work outside that set. Propagate failures rather than merely logging and proceeding as if complete.

3. **Lazy-list positioning still guesses and may correct too early.** `source_catalog_screen.dart:761` estimates a 540-pixel header and 56-pixel rows; reader Contents estimates 54-pixel rows. A single `ensureVisible` retry only works if the estimate built the actual target. For animated jumps, the retry runs on the next frame without awaiting the 300ms animation. Long wrapped lists can still miss entirely. Use genuine indexed positioning or a bounded locate/measure loop, await layout/scroll completion, and set `_hasInitialScrolled` only once the target is actually reached.

4. **EPUB export is still not safely responsive/atomic end to end.** `epub_export_service.dart:243` synchronously compresses the entire archive on the UI isolate. Yielding every 20 chapters does not move compression or reduce total memory use. The file-save block deletes the previous EPUB before renaming the replacement, so a failed rename loses the previous export. Earlier read/parse/directory errors still occur outside that catch. Move CPU-heavy work off the UI isolate, use a consistent export snapshot and unique temporary filenames, preserve existing output until replacement commits, and return actionable errors for the entire operation.

5. **Images can be silently discarded and XML validation remains incomplete.** The exporter removes every image it cannot resolve as a managed local file, including relative paths that are not resolved against the chapter location and data URIs. There is no omitted-image count/warning. Do not equate deleting an image with preserving a portable illustrated book. Handle supported resources explicitly and report omissions. `toValidXhtml` still only regex-patches three void elements; serialize/validate XML properly before describing output as a fully validated EPUB.

6. **Cancelling Save As opens another picker.** In `saveExportedEpubAs` at approximately line 400, Android returning false falls through to `FilePicker.platform.saveFile`. Return a cancellation result immediately. Use the other picker only on a supported fallback platform/path. Keep cancelled and failed outcomes distinct: the current UI says “Save cancelled” even for exceptions/disk/provider failures. Restrict FileProvider roots to export locations instead of all of `app_flutter`, files and cache.

7. **Notification rendering is aggregated; foreground ownership is still per worker.** Each chapter still calls `setForeground` with ID 4001. A shared map and notification builder do not transfer WorkManager foreground ownership to one queue-level worker/service. Address completion/foreground lifecycle so one worker's teardown cannot remove another's ongoing notification. This is an outstanding structural risk, not a claim of a newly reproduced phone failure.

8. **Activity-wide blur is not reader-toolbar backdrop blur.** `ReadiumReaderActivity.kt:450` adds `FLAG_BLUR_BEHIND` to the activity window. That blurs windows behind the reader, not prose behind controls inside that same window. It can be appropriate for a separate dialog, but does not establish native toolbar parity with Flutter backdrop glass. Apply a suitable bounded material implementation to reader controls and use correct dialog/background blur where appropriate, with disabled-blur/accessibility fallback. Android explains the distinction in its [window blur documentation](https://source.android.com/docs/core/display/window-blurs). Also apply changed Window LayoutParams through the window setter rather than relying solely on mutating the returned attributes.

Source diagnostics have improved but still gate the explicit search test on the empty-listing health result; a broken default listing can prevent testing an otherwise working search. Keep stages independent, and do not represent untested listings as verified.

### Prompt to send now

Continue the full Hon app with repositories/extensions bundled. Preserve the improvements listed above. Fix the remaining numbered findings in this latest recheck, prioritizing saved-content integrity and batch download coordination, then navigation/export, then native UI. Do not repeat already completed changes or treat the older historical findings below as all still open.

Use stable chapter/job identities and attempt-aware cancellation. Preserve downloaded illustrations, reading progress, bookmarks and library membership. Provide accurate success/cancel/error states. Do not claim a requirement is complete from a renamed helper or a green test that bypasses the native integration.

Perform only focused verification after the fixes: offline images survive reload; batch pause cannot affect a new attempt outside its snapshot; distant wrapped chapter rows can be reached; Save As cancellation returns once; export failure preserves the previous file. Keep device-only visual and lifecycle checks on a short user checklist. No repeated broad test sweeps. The no-bundled-repositories release and Google Play edition remain deferred until the full app is finished.

---

## Previous recheck — historical evidence

21 October 2026. Reviewed the current local code and the supplied implementation report. No tests, builds or device checks were run by this reviewer. Reported test/compile results are Antigravity's results, not independently reproduced here.

**Verdict: useful progress, but more code fixes remain before only phone testing is left.** This document supersedes the status of corresponding findings in the earlier review; retain that document's requirements and deferred distribution plans.

## Confirmed improvements in code

- System brightness now defaults to `-1`, and both preference deserialization and native typography ingestion preserve that value.
- EPUB appearance now reads the shared `appAppearanceKey`.
- Individual cancellation acknowledges Dart after `stopJobDurableAndAwait`, and deletion retains files if that cancellation throws.
- Batch refresh events use a null job ID, fixing the previous `ALL` lookup problem; batch cancellation now also retrieves persisted IDs.
- Missing chapter files can pass managed-path validation for reconciliation; chapter deletion is restricted to the chapter root.
- Custom next-N and delete-unread actions exist in the shared coordinator and both catalogue UIs.
- Web-novel reader has a catalogue-back action and a lower reload control, although reload itself is broken below.
- Flutter reader popup, Contents and settings now have rich-mode branches.
- The sanitizer is now called by normal web-novel reader loading, including saved chapter content. The earlier “export only” finding is no longer current. The broad translator-attribution removal rule has been removed.
- Novel Parsing and Passage Fetching are marked Not tested rather than incorrectly Working.
- EPUB export has illustration-bundling code and a Share action, but both have integration bugs below.

## Remaining findings

### 1. Reload immediately skips the reload — high priority

Evidence: `lib/features/reader/presentation/reader_screen.dart:1919` and `:85`.

`_reloadCurrentChapter` inserts the index into `_loadingChapters` before calling `_ensureChapterContent`. That method immediately returns when the index is already in `_loadingChapters`. Existing nonempty HTML is a second early-return condition. The control still reports “Chapter reloaded,” even though no reload happened, and the loading marker remains set.

Fix with an explicit refresh path that bypasses the content cache intentionally, has one owner of the loading marker, restores it in `finally`, retains the reading anchor, and reports actual success/failure. Define whether reload rereads the local file or explicitly refetches online. Avoid throwing away usable content before a replacement succeeds.

### 2. EPUB Share uses a directory outside FileProvider's configured roots — high priority

Evidence: `lib/core/export/epub_export_service.dart` output-directory block; `android/app/src/main/res/xml/file_paths.xml`; `HonReaderBridge.kt:402`.

The export goes to Flutter's application-documents directory (`app_flutter/exports` on this Android setup). FileProvider exposes native `files/`, `cache/`, external files and external cache. None covers `app_flutter/exports`, so `getUriForFile` cannot provide a URI for the normal export output. The Dart helper catches failures and returns false; the snackbar callback ignores that return value, so the failure can be silent.

Android documents that `<files-path>` refers to `Context.getFilesDir()`, and FileProvider only serves configured directories: [official FileProvider reference](https://developer.android.com/reference/androidx/core/content/FileProvider).

Fix by placing/copying shareable exports into a narrowly configured native cache/export directory, or another correctly scoped location. Do not expose the whole app data directory as a shortcut. Show sharing errors. Add the requested persistent Save As option as well as Share.

### 3. Export illustration handling misses the downloader's URI format

Evidence: `OfflineChapterImages.kt:200` uses `dest.toURI().toString()`; `EpubExportService._bundleIllustrations` only converts strings starting with `file://`.

Java's local File URI can be `file:/...`, which fails that prefix check. It is then passed to `File()` as a literal path and not bundled. Existing chapters with that format retain private-device URLs in the exported EPUB.

Fix by parsing the URI and checking `scheme == 'file'`, handling valid `file:/` and `file:///` forms with URI decoding. Resolve plain relative paths against their chapter file. Restrict local reads to managed illustration resources, validate supported media, and insert deduplication entries only after successful reads. Report missing resources. Account for data URIs and cover caching as required for a portable export.

### 4. Jump-to-current still fails for distant chapters in lazy lists

Evidence: `source_catalog_screen.dart:761`, `:777`, `:1804`; `reader_contents_sheet.dart:86` and its `ListView.separated`.

The source catalogue calls `ensureVisible` only if the current chapter's GlobalKey already has a context. Off-screen rows in `SliverList.builder` are not built, so jumping to a distant chapter does nothing. The reader sheet falls back to the old 54-pixel estimate and does not correct its position once the actual target is built. Wrapped titles still invalidate that estimate.

Use real index-aware positioning or a reliable bounded locate-and-align approach, then align the actual row. Resolve the displayed index from stable chapter identity and sorting. Handle cached/offline loading and only perform the initial automatic jump once. Do not build thousands of rows eagerly to make keys exist.

### 5. Queue notification ownership and batch concurrency remain partial

Evidence: `DownloadNotifications.kt:17`, `HonDownloadWorker.kt:123`, `:161`, `:198`; `HonDownloadManagerBridge.requestAllJobsStopped`.

Foreground promotion moved behind the gate, which helps. However each concurrently running worker still owns/updates ID 4001; this is not a queue-level owner. The title/progress can be overwritten by another chapter, and completion/lifecycle behavior still needs proper aggregate coordination. The values 10/75/100 are fixed phase markers, not measured transfer percentages. Use indeterminate progress or clearly labeled stages when actual progress is unavailable.

Batch cancellation also unions the persisted target IDs with every process-local scheduling-lock key. It does not acquire the same per-job scheduling locks, and commits token removals only after stopping workers. A concurrent resume/enqueue can be cancelled outside the intended snapshot or have its new token removed. Fix batch scope and ordering under the same coordination as scheduling; invalidate only the captured attempts before awaiting their termination. Do not silently swallow batch errors. Provide a real aggregate notification lifecycle and appropriate pause/resume behavior.

### 6. EPUB export still lacks reliable loading, error handling and large-book handling

Evidence: `epub_export_service.dart:34`, ZIP/output blocks, and `library_screen.dart:599`.

The Library action still does not call `ensureChaptersLoaded`, and the service still reads the in-memory chapter list directly. Export can therefore miss durable chapters that have not been loaded. The service still builds the complete archive in memory and ZIP-encodes synchronously on the UI isolate. Read/write failures can escape instead of becoming an actionable export result, and output is written directly to the final filename.

Hydrate chapters; snapshot eligible files; use background/streaming work for large exports; handle errors/cancellation and finalize atomically. Validate actual XML/XHTML rather than relying on regex self-closing of three tags. The current two export tests do not establish Android sharing, actual downloaded illustration portability, or large-series behavior.

### 7. Source diagnostics are more honest, but search is still inferred

Evidence: `source_health_service.dart:38` and `diagnoseSource`.

The service calls one empty-query listing request and uses its success to label Search as Working. It does not demonstrate that a nonempty search query works, and it ignores whether the returned result set was empty. Listing metadata is not proof that each listing works.

Keep untested operations Not tested, or perform a bounded explicit probe for that operation. Treat empty results separately from exceptions. Do not equate this diagnostics change with fixing all failing sources.

### 8. Native EPUB glass still does not match Flutter glass

Evidence: `ReadiumReaderActivity.kt:318` versus the Flutter reader sheets.

Native `getBarBackgroundColor` still implements rich mode as 82% alpha. There is no equivalent native backdrop material in the inspected implementation. Flutter sheets now have blur, so the parity requirement remains partial. Complete matching reader controls/materials after functional fixes, preserving solid Standard reader surfaces, solid prose backgrounds and accessibility fallbacks.

## Focused follow-up prompt

Continue from the existing changes; do not rewrite completed work. The latest code recheck still finds the eight issues above. Fix them in this order:

1. Broken chapter reload and false success messaging.
2. Android EPUB sharing directory mismatch, silent errors, and Save As.
3. Export image URI handling, durable chapter loading, safe resource packaging, valid XHTML, error handling and large-export responsiveness.
4. Accurate current-chapter positioning for lazy long lists.
5. Queue-level notification ownership and batch cancellation/enqueue/resume coordination.
6. Operation-specific source diagnostics; repair demonstrated source failures without disturbing working sources.
7. Remaining native/Flutter reader appearance parity.

Keep bundled repositories/extensions throughout this pass. Removing bundled repositories and creating a Google Play edition remain deferred until the full app is finished.

Preserve the brightness, appearance-key, individual cancellation acknowledgement, batch refresh, managed missing-file handling, bulk actions, catalogue navigation and sanitizer improvements already made. Keep bookmarks, progress, library membership and downloaded content intact.

Do targeted verification only after implementation. Cover the actual failure paths: Reload invoking a real load; sharing a default-location export; an image URI produced by the native downloader; a distant chapter in a lazy list with wrapped titles; and overlapping batch pause/resume. Avoid another broad test sweep merely to repeat previous green results. Retain a necessary native compile check after native changes and give the user a short phone checklist.

Update progress honestly: implemented code, targeted verification and phone verification are different statuses. Do not claim “all resolved” while any above path is incomplete. Return a requirement-by-requirement delta with remaining limits.
