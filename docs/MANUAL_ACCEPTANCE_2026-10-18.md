# Short phone check for this release

> Superseded by [Hon 1.1.1 and current APK](APP_CURRENT_2026-10-19.md). This document records an earlier milestone.


Install [the release APK](../build/releases/Hon-2026-10-18-phase1-polished.apk) over the current app; keep its data. No uninstall is required. This is the project's existing local signing setup, not a newly configured store release.

1. **Sources/repositories:** Browse should contain the bundled Shosetsu collection instead of the Gutenberg-only default. Try language search, a source listing, Load more where offered, and one novel/chapter. In Settings → Extension repositories, add/cancel/add an invalid URL, then a valid repository. No red-screen assertion; errors remain recoverable. Test disabling/removing one source and restarting; it should stay disabled/removed.
2. **Fonts:** In a downloaded novel and the Lord of the Mysteries EPUB, choose Newsreader, Literata, System Sans, Lora and Libre Baskerville under Aa → Themes & Settings → Customize. Faces should visibly differ and survive closing/reopening. For EPUB, choosing a face turns off publisher typography. Fixed-page PDF/EPUB content does not offer a working font-reflow promise.
3. **Reader consistency:** All readers should use a location/close header and bottom Aa menu. Check Contents, bookmarks, six themes, EPUB book search, PDF page jump/zoom, quote sharing in the two text readers, rotation, and saved position. In both text readers, check Paged and continuous vertical chapter transitions.
4. **Home/performance/data:** Check Continue, recent books, offline books and daily goal. Try scrolling/opening menus in this release build. Open/close the EPUB after more than 30 seconds; no late timeout. Confirm old library entries and downloads remain; read one downloaded chapter/image offline.

Report a checklist number and what happened if something fails. Live website failures should be visible errors, not false empty results. There is no need to test every source or repeat unrelated checks.

Phase 1 additionally changes downloaded-book search, lazy chapter loading, adaptive Library grids, explicit Finished filtering, source pins, and Downloads/Ready Offline controls. The short [Phase 1 check](PHASE1_COMPLETION_2026-10-18.md#short-phone-acceptance) covers these without asking you to test all websites.
