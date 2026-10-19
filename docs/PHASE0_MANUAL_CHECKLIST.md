# Phase 0 — checks for the user

> Superseded for the current build by [the repair/design handover](REPAIR_AND_DESIGN_HANDOVER_2026-10-18.md) and [new short release checklist](MANUAL_ACCEPTANCE_2026-10-18.md). Use the release APK linked there.

Install `build/app/outputs/flutter-apk/app-debug.apk` over the existing app. Keep the existing installation and its data. This APK includes changes made after the short phone check; those changes have not been tested on your phone.

Use **Lord of the Mysteries Book 1**, a downloaded novel, and a PDF. Stop at a failure and report its checklist number and what happened.

1. **EPUB:** confirm the library cover; open, read for over 30 seconds, close, reopen. No late timeout; position should return. Use the star button to save/reopen/remove a chapter bookmark.
2. **Both novel readers:** try Paged and Scroll; cross a chapter boundary in each direction. Change font size/theme, rotate, close/reopen; the same passage should remain nearby. Try orientation lock/unlock. In EPUB Scroll mode, keep dragging vertically through the end of one chapter into the next, then back. There should be no horizontal swipe requirement. Fixed-layout EPUBs use Paged mode.
3. **Quotes:** select a short passage with a line break in each novel reader and choose Share quote. Inspect the chooser text for the exact selection and available author/title, then cancel. PDF text selection is not supported by the current raster renderer.
4. **Search:** compare Browse and global Search for the same Gutenberg query (for example `pride`). Try a query with spaces and then airplane mode; a source failure should show an error/retry rather than a false empty result.
5. **Repositories:** Settings → Extension repositories → add/refresh a compatible Shosetsu repository → install a source → browse/search/open a chapter. Disable/re-enable it, then remove its repository. Existing books/downloads must remain. The WordPress/Bixbox/Madara core families have local fixture coverage. Unsupported host APIs and website failures must show errors; compatibility with every third-party source is not guaranteed.
6. **Downloads:** download a chapter without adding its novel to Library. Check Downloads, background/reopen the app, then use airplane mode and read the downloaded text/images. Retry/cancel a job. Android force-stop suspends background work until the app is reopened.
7. **Removal and PDF:** “Remove from Library” must preserve files/progress and support Undo. Test “Remove from Library and Delete” on a disposable import/download; external original files must remain. For a PDF, check page navigation, zoom, bookmarks and position after reopening.

Phase 1 is the visual design pass. Record these outcomes before declaring functional acceptance complete.
