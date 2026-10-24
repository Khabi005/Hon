# Hon 1.1.0 — remaining implementation completed

> Superseded by [Hon 1.1.1 and current APK](APP_CURRENT_2026-10-19.md), which closes Reading History/themed-icon gaps and improves Home. This file records the prior implementation pass.

This handover supersedes the older Phase 0/Phase 1 APK links and unfinished-feature lists. It covers the remaining features listed after the Phase 1 UI pass. Device acceptance is pending the user's next phone test.

## Install

Use [Hon 1.1.0 complete](../build/releases/Hon-1.1.0-complete.apk), an optimized release build with the same local signing identity as the previous Hon APK. Install over the current app and keep its data.

## Verified release files

| Build | Bytes | SHA-256 |
| --- | ---: | --- |
| Update-compatible complete APK | 74,968,600 | `c5623f26cf03618d5daf4f191b247c48e6917f3b2b0626223bf29111e14acb17` |
| Dedicated-key production APK | 75,048,743 | `ce6918f778ed9f34602a8b1d9ace77ae7da287dc6ce54d47e4a2ccbc42effcce` |

Both are version **1.1.0+2**, non-debuggable, with matching app payloads. Signature verification, all 172 bundled source hashes, eight fonts and the native EPUB JavaScript resize method passed. JSON verification reports and checksum sidecars sit alongside each APK in `build/releases/`.

The complete APK certificate matches the previous Phase 1 build: `2a33e768770e1d3b5331dbe5a450b9d21e1cbccde9f1c6aba329ead6ad9a02b7`. The dedicated production identity is `a0a8197fb1e0b99e55b7992db83f208e41f32ed53e4e5268afec671730852f0a`; use the complete build for the existing installation. The final production APK is signed from the verified complete build's payload, so both contain the last restore/resume correction.

## Delivered features

| Area | What now works |
| --- | --- |
| Collections | Create, rename, delete and assign books to multiple collections. Library filtering and membership survive restart. Deleting a collection keeps its books and files. |
| Chapter updates | Check one novel or the library against its real source. Durable newly-discovered chapter history, visible per-novel errors, read/download actions, preserved saved files and stable reading chapter when upstream order changes. |
| Downloads | All missing, unread, individual and chapter-range selection; durable batch queue, duplicate protection, pause/resume per job or in bulk, retry and Wi-Fi-only preference applied to native work. |
| Source controls | Source-declared text/password, switches, dropdowns, radio and tri-state controls. Saved search filters apply to source/global search. In-app HTTPS website sign-in sessions are scoped to the selected source and shared with browsing and chapter workers. |
| Backup/restore | ZIP export of books, collections, progress, bookmarks, jobs and reading/source preferences, optionally including managed publications, covers and saved chapters. Restore preview, safe path/size/checksum validation, transactional database import, rollback and portable file relocation. |
| Release preparation | Version 1.1.0+2, dedicated private signing setup, explicit compatible local release option and [release instructions](RELEASE_GUIDE.md). |

The 172 bundled Shosetsu source snapshots, reader fixes and Phase 1 visual/smoothness work remain included. PDF uses the same reader control conventions with page/zoom tools; fixed PDF text cannot reflow into the selected text-reader font.

## Reliability and responsiveness

- Persist the whole chapter selection before scheduling, so closing Hon during scheduling cannot discard the remaining selection.
- Serialize attempts for each chapter; a revoked attempt cannot overwrite a resumed job. Pause cancels its HTTP requests and waits for file replacement or rollback to settle before acknowledging.
- Start interrupted-download recovery after the app's first frame instead of blocking first display.
- Use lazy lists for large chapter pickers and source-control sets; avoid repeated whole-queue scans during batch scheduling.
- Metadata-only restores recreate a managed chapter destination when a paused job is resumed on the new device.
- Backups pause work first, compress/extract away from the UI isolate and verify file hashes. Existing files are not overwritten during restore; failed database imports remove newly extracted files.
- New layouts support larger text and narrow screens. Header actions move to a second row when needed.

## Local verification

- Static analysis: clean.
- **16 Flutter checks passed:** collections persistence; real update history/deduplication and changed chapter order; portable Unicode backup and file/locator/bookmark restore; unsafe/corrupt archive rejection; invalid-reference rejection; actual SQL rollback; secret exclusion; batch queue/pause/resume and restored destinations; interrupted-download recovery; existing chapter merge/library/download/reader UI regressions; chapter picker and source-control reset/save behavior.
- **3 Kotlin checks passed:** typed source settings/filter execution and invalid-value rejection; source-scoped HTTPS cookie policy.
- Ten local fixture layouts rendered without Flutter exceptions. Inspected collections, library at larger text, update history, backup, bulk picker and source controls including dark/large-text layouts.
- Optimized Android packaging, certificate/asset/version checks are recorded with the release artifacts.
- No automated phone session or broad live-site probe was performed.

## Practical limits

- Website availability, accounts, captcha challenges and extension changes remain source-dependent. Shipping every bundled extension does not prove every website is currently usable. Live failures must remain visible and recoverable.
- Update checks are user-triggered. Initial checks can discover previously uncached chapters, so the history says newly discovered rather than claiming a publication date. Legacy novels missing their source URL need opening from Browse once.
- Metadata-only backups require reimporting missing EPUB/PDF files or downloading chapters again on a new device. Included files are limited to managed Hon storage. Limits are 256 MB per file, 2 GB total uncompressed data and 20,000 files; larger publications can be transferred separately.
- Website sessions and declared credential fields are excluded from backups. Custom repository definitions/preferences are preserved; custom extension code can be reinstalled from those repositories. This is portable local backup/restore, not cloud synchronization.
- Smoothness was improved in code and local renders; actual phone behavior and frame performance need the user's acceptance check. No all-device or all-source guarantee is made.

## One short phone pass

1. **Update and readers:** install the complete APK over Hon. Confirm old library/files remain. Open the supplied EPUB, a PDF and a downloaded novel; check fonts where supported, themes, chapter transitions, rotation, bookmarks, position restoration and closing the EPUB after 30 seconds.
2. **Library and updates:** create a collection, assign/filter a book and restart. Check updates on one online novel and open a discovered chapter.
3. **Downloads:** choose a small range of 2–3 chapters, pause/resume, then read offline. Toggle Wi-Fi-only if useful. No need to queue an entire long novel to test it.
4. **Sources:** open one source's controls, change an available filter and save. Try Website / Sign In only if that source requires it. Try adding/cancelling a repository and confirm no red error screen.
5. **Backup:** save a small backup including files; inspect the restore preview. Restore when comfortable with matching books taking the backup's saved progress.

Report a number, the book/source and what happened. There is no need to test every source or run development tools.

## Preview files

These are local fixture renders, not phone captures:

[Collections](completion-previews/collections.png) · [Library with larger text](completion-previews/library-large.png) · [Updates](completion-previews/updates.png) · [Backup](completion-previews/backup.png) · [Chapter picker](completion-previews/bulk-large.png) · [Source controls, dark](completion-previews/source-controls-dark.png) · [Source controls, larger text](completion-previews/source-controls-large.png)
