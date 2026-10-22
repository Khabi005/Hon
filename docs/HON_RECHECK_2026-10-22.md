# Hon — latest implementation recheck

## Follow-up review of the subsequent six-item implementation report

**This is the current status; the earlier assessment below is historical.** Inspected the updated code without running tests, analysis or builds. The export error handling, omission warnings and Android compression-failure behavior are improved. Reload retains memory-only safety and now has explicit outcomes, but its enum was declared in an invalid location.

### Fix these concrete remaining issues

1. **Compile blocker: nested Dart enum.** `reader_screen.dart:85` declares `enum ChapterLoadResult` inside `_ReaderScreenState` (which opens at line 58). Dart enum declarations must be at library scope. Move it outside the class; retain the explicit result handling. This is a source-level finding, not the output of a compiler run.

2. **Batch cancellation creates a database/worker lock-order problem.** In `HonDownloadManagerBridge.stopAllJobsDurableAndAwait`, `db.beginTransaction()` occurs before acquiring each scheduling lock and before `HonDownloadWorker.stopAndAwait`. Workers perform database writes before releasing their worker mutex. Scheduling also takes a scheduling lock before consulting the database. The batch can therefore hold the database writer lock while awaiting a worker or scheduling lock that is waiting on that database. This risks long stalls, lock errors, or deadlock-like behavior. Do not hold a SQLite write transaction while awaiting worker termination. Acquire the job's scheduling lock, verify/invalidate the captured attempt, stop/await the worker, then use a short database transaction to update the conditional job/chapter state before releasing coordination. Keep completed-state protection. Handle partially stopped batches explicitly if a later target fails.

3. **The rendered-index set is not a current viewport measurement.** Both lists add indices in item builders but do not remove them when rows leave the viewport. They clear the set during programmatic jumps, but retained rows are not guaranteed to rebuild merely because the set was cleared. As a result, min/max can describe old rows or an incomplete current set. If the target is between those stale bounds but not actually built, the loop chooses the same offset repeatedly. In the source catalogue, `_renderedChapterIndices.add(index)` records canonical indices while `targetPosition` uses reversed display positions when reverse sorting is enabled. Use actual visible/mounted row tracking or an indexed scrolling component, with one consistent display-index space. Do not treat a set populated during building as visibility evidence.

4. **Notification fallback does not resolve foreground ownership.** The added `NotificationManager` fallback on `setForeground` failure only displays a notification; it does not establish foreground execution or one queue owner. Each worker still supplies shared ID 4001 to WorkManager. The earlier lifecycle concern remains. Report it as unresolved until worker completion/promotion cannot remove or restore a stale notification for the remaining queue. Use real queue-level foreground ownership or a justified lifecycle design, rather than another notification-rendering helper.

5. **Native glass fallback is not actually solid.** `updateThemeStyling` uses `barBg = getBarBackgroundColor()` in both branches. That helper still returns an alpha color whenever `isGlass` is true, even when `isBlurAllowed()` is false. The fallback therefore drops the border but retains translucency. Make the fallback color explicitly opaque, update it when runtime blur/battery state changes, and retain native toolbar parity as partial: the inspected bars still do not render an equivalent bounded backdrop material.

### Improvements verified by reading

- Reload's outcome branches and consumer have been updated; move the enum rather than discarding that work.
- Export now catches operation errors, does not synchronously retry compression on Android, directly renames within the output directory, and shows omitted-image counts in both UIs.
- XML comments and the serialization fallback have received additional handling.
- Cancellation now checks strict token equality and protects completed/downloaded status. Preserve those rules while correcting lock order.
- Chapter navigation now attempts multiple jumps instead of merely waiting, but its index tracking remains unreliable as described above.

### Prompt for the next implementation step

Fix the five findings in this latest follow-up. Start with the enum placement and cancellation lock order. Preserve the completed reload/export/Save As/source-diagnostic improvements. Trace actual state ownership and synchronization, including which code holds the worker mutex, scheduling lock and database writer lock. Do not wait for a worker while holding the writer transaction it needs to finish.

Use reliable visible-row/index tracking, correct reversed sorting, and accurate completion status. Complete notification ownership and opaque native fallback rather than relabeling partial implementations as done. If full native glass parity remains unfinished, say so explicitly.

Keep repositories/extensions bundled and distribution changes deferred. Do not run tests, static analysis or builds in this step. Return the exact changes and remaining limitations; propose the smallest necessary checks afterward. Do not claim previous check results cover these new edits.

---

## Earlier October 22 assessment — historical

22 October 2026. Static inspection of the local code and the latest Antigravity report. No tests, analysis commands, builds or device checks were run. This is the current follow-up; older reviews describe earlier versions.

## Verdict

More requirements have been addressed, but **“all implementation items complete” is still not accurate**. There is a return-type blocker visible in the code plus remaining state-management and positioning gaps.

## Improvements to preserve

- Forced reload no longer writes over the downloaded file. Offline fallback is tracked separately for messaging.
- Android Save As returns after cancellation and distinguishes saved/cancelled/failed results.
- FileProvider roots are now restricted to export folders.
- EPUB compression normally runs through `compute`; relative and inline image handling, an omission count and XML-node serialization have been added.
- Search diagnostics no longer depend on the default listing succeeding.
- Batch cancellation captures attempt tokens and scopes affected IDs instead of updating every active job.
- Activity-wide blur was removed; dialog blur now applies updated window attributes explicitly.

## Remaining fixes

### 1. Fix the reload method's return contract first

`lib/features/reader/presentation/reader_screen.dart:85` declares `Future<bool>`, but lines 135 and 138 still use bare `return;`. Its non-forced error path also falls through without a boolean. This is incompatible with the non-nullable return type, visible by inspection; no compiler was run.

Return a valid result on every path, or preferably introduce an explicit result for refreshed/offline fallback/skipped/failed. Keep cleanup in `finally`. Preserve memory-only behavior and do not restore the removed file write.

### 2. Finish batch cancellation coordination

In `HonDownloadManagerBridge.requestAllJobsStopped`, each per-job lock is released before the later SQLite updates. A new attempt can be scheduled for the same ID in that interval, and the later ID-only update overwrites its state. A null snapshot token is also treated as permission to cancel regardless of the current token.

Additionally, the new SQL unconditionally updates stopped job/chapter IDs. If an in-flight attempt completed before cancellation took effect, it can be changed from completed/downloaded into paused/notDownloaded while its file still exists. Preserve completed state.

Perform cancellation and conditional durable state updates under the same scheduling coordination, check the captured generation/attempt, and do not treat a missing token as a wildcard for a newer attempt. Update jobs and chapters transactionally; retain completed downloads. Surface failures instead of reporting success after logging them.

### 3. A waiting loop is not index-aware chapter navigation

Both catalogue and Contents still make one estimated jump using fixed row heights, then wait three frames at that same position. If the estimate missed the target because titles wrap, waiting does not build that distant row. `source_catalog_screen.dart:810` also sets `_hasInitialScrolled = true` after all retries fail, contradicting the report's claim that it is only set after centering succeeds.

Use an index-aware list or a bounded positioning algorithm that actually changes its estimate based on visible/measured rows. Mark success only after the real target is aligned; maintain sorting and stable chapter identity.

### 4. Export is improved but its guarantees are overstated

- The catch around `compute` falls back to synchronous compression on the UI isolate for any error. Remove that fallback on Android; return an actionable error or use another background path.
- The backup-copy fallback can leave a partially copied final EPUB if the process stops, with the previous version only in a `.bak`. There is no recovery protocol in this export path. Prefer same-directory atomic replacement; on failure preserve the old file and report the error, or implement explicit recoverable staging.
- File reads, URI decoding and output-directory creation still occur outside the final write catch. Convert failures across the complete operation into an export result.
- `omittedImageCount` is returned but is not referenced in Library/Browse presentation. Show an omission warning with the export actions.
- XML serialization is an improvement, but copying comment contents unchanged can still produce invalid XML comments containing `--`; the regex fallback also does not establish valid XHTML. Avoid claiming validated EPUB output without validating the produced documents/resources.

### 5. Notification ownership remains an unresolved structural risk

Each chapter worker still calls `setForeground` with shared notification ID 4001. Moving cleanup into `finally` and maintaining an aggregate map improve rendering but do not establish one foreground owner for the queue. Complete lifecycle coordination so one worker finishing cannot remove the notification needed by another. The report's listed code changes do not prove that ownership issue resolved; no device failure is claimed here.

### 6. Native reader glass parity remains partial

Removing activity-wide blur corrects the earlier misuse. The native top/bottom bars still use translucent colors/strokes; separate dialog blur does not itself create bounded backdrop glass in reader bars. Report this as partial pending the actual toolbar material work and visual review. Touch exploration is also not a substitute for all reduced-motion, high-contrast and runtime blur-availability handling.

## Prompt for Antigravity

Continue from the latest implementation. Fix the six remaining items in this October 22 recheck, beginning with the non-nullable reload return contract and cancellation state races. Preserve the improvements listed above; do not redo fixed work.

Keep bundled repositories/extensions. Both distribution changes remain deferred until the full app is finished. Preserve downloaded files/images, completed job states, progress, bookmarks and library membership.

Do not run tests, analysis commands or builds during this implementation step. Review every edited call path and every return/exception path. When finished, report precise changes and unresolved limitations, and propose the smallest necessary verification pass. A previous successful compile does not cover these new edits.

Do not mark a requirement complete solely because a method now has the expected name, waits a few frames, or returns a new field. Verify through code inspection that the caller consumes that result and that the entire state transition implements the requirement. Distinguish code implemented, checks not run, and phone verification pending.
