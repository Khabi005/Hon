# Phase 1 — UI completion and smoothness

> Superseded by [Hon 1.1.1 and current APK](APP_CURRENT_2026-10-19.md). This document records an earlier milestone.


## Status and scope

Phase 1's UI implementation is complete for the current app screens: Home, Library, Browse, source catalogs/details, Downloads, global Search, Settings/repositories, and the three reader formats. This completes the first-pass design milestone with a consistent visual system and working controls. Physical-device acceptance and measured frame performance remain pending; local widget renders are not phone screenshots. Existing Phase 0 functionality and the bundled 172-source catalog are retained.

This milestone does not claim completion of every future feature in the original brief. Collections management, full chapter-update tracking, advanced source settings/authentication UI, and any later backup/sync work are separate product capabilities. The placeholder Updates screen was replaced by an actual Ready Offline shelf rather than advertised as implemented chapter-update tracking.

## Deliverable

[Install the optimized Phase 1 APK](../build/releases/Hon-2026-10-18-phase1-polished.apk) — **73.7 MB** (73,673,536 bytes).

- SHA-256: `8fef75b22f7c0c774eac985729dce5656dfac2b158091971cb754109e9fb50e6`
- Signature verified; certificate matches the prior Hon APK (`2a33e768770e1d3b5331dbe5a450b9d21e1cbccde9f1c6aba329ead6ad9a02b7`). Install over the existing app without uninstalling. This uses the project's existing local signing setup, not a store-signing migration.
- Verified the packaged catalog's 172 Lua bundle hashes and all eight font files.
- Release shrinking retains the EPUB resource-height JavaScript bridge method name.

## Completed

- **Shared styling:** coordinated light/dark surfaces, improved secondary-text contrast, consistent dialog/sheet shapes, field/button styles, minimum touch targets, and bundled serif headings. Reader controls retain each reader's selected theme.
- **Navigation:** readable compact-phone and large-text treatment, selected-tab semantics, tooltips and badges, keyboard dismissal on switching, back-to-Home behavior, retained tab state, inactive-tab focus/ticker suppression. The continuously blurred bottom bar is now an opaque elevated surface.
- **Home:** quieter Continue cards with real progress, muted generated covers, correctly ordered library additions, larger-text-aware shelves/cards, preserved empty-state shortcuts and real reading-goal data.
- **Library:** adaptive 2:3 covers from narrow phones through tablet widths, uncluttered cover art, scaled label space, accessible book options, persistent grid/list and sort choices, distinct EPUB/PDF/novel filters, explicit Finished state, and correct filtered-empty messaging. Visible Library now listens for database updates.
- **Browse and catalogs:** shared segmented controls, direct repository access, working source pins, readable source rows, responsive catalog cover grids, and no redundant cramped Browse buttons. Global source-result groups build lazily.
- **Novel details:** chapter lists build lazily, sort order works, each chapter's download action works, and saved chapters show their offline state. Adding a novel to Library saves its actual metadata/chapters first. Original creation dates and existing saved-chapter state are preserved.
- **Downloads:** actual queued/running/retry/failed/paused/cancelled/completed labels, progress, retry/cancel/read controls, busy/error feedback, and a Ready Offline shelf based on publication/chapter records. Saved-file totals no longer rely on completed queue history. Clearing completed history keeps files.
- **Reader consistency:** downloaded, PDF and EPUB share location/close/progress/Aa conventions, six named themes, and format-appropriate tools. Appearance has a real typeface preview; EPUB uses the same preview text and fonts. Line spacing, margins, paragraph spacing and indent are exposed for reflowable text. PDFs retain page/zoom controls rather than ineffective typography settings.
- **Reader interaction:** control animations use paint transforms and respect Reduce Motion. Hidden Flutter controls leave touch and accessibility navigation. Reader text-layout sliders apply once at release while brightness can preview live. Sheets scroll within the available height in landscape and with larger text.

## Concrete smoothness and data fixes

1. ZIP/XML EPUB parsing runs in a worker isolate. Import/cover repair request metadata-only parsing, avoiding copying every chapter body into the UI isolate.
2. Opening a downloaded novel reads the requested chapter asynchronously. Other saved chapters load when needed, instead of synchronously opening every chapter file before the reader appears.
3. Search Book scans saved text in a worker isolate when explicitly submitted. It includes unopened local chapters, displays excerpts, and navigates to the selected chapter.
4. Chapter updates merge into the cached chapter list and persist only changed rows. Updating one download no longer replaces the rest of the novel's chapter list in memory.
5. Novel chapter rows and source-result sections build lazily; saved-chapter lookup maps avoid rescanning the whole chapter list for every row.
6. Inactive database-backed tabs stop subscribing their widget trees to frequent database changes; already visited tabs retain their state. Tab and reader chrome repaint boundaries isolate drawing.
7. Prior fixes remain: cached Lua prototypes with fresh execution state, cover decode sizing, bounded network concurrency, and removal of whole-catalog JSON rewrites on progress saves.

## Verification

- `flutter analyze --no-pub`: clean.
- **12 focused regression checks passed:** library format/finished filters, live library updates, true download states/offline shelf, deferred slider commit, unopened-chapter search, partial chapter updates across cache/SQLite, EPUB parsing/metadata-only parsing, preferences, and downloaded-reader page/scroll transitions.
- Local renders inspected at 390×844, 320×740 with 1.4× text, 844×390 landscape, and 800×1100 tablet. Home light/dark, Library, Downloads, Browse with all 172 entries, Settings and appearance were inspected. Two concrete overflow/wrapping defects found in these renders were fixed.
- Native EPUB changes compile in the optimized Android release build.
- No phone automation, data reset/export, broad live-site probes, or claim of measured FPS.

## Previews

These are local widget renders with fixture books and generated fallback covers. They demonstrate layout, not a user's library or native EPUB/PDF screen captures.

- [Home](phase1-previews/home.png) / [Dark Home](phase1-previews/home-dark.png)
- [Library](phase1-previews/library.png)
- [Browse](phase1-previews/browse.png)
- [Downloads](phase1-previews/downloads.png)
- [Appearance](phase1-previews/appearance.png)

## Short phone acceptance

Install the Phase 1 release over the current app. Check:

1. Open a long downloaded novel: opening, chapter transitions, Search Book, fonts and scroll/page switching.
2. Open the provided EPUB and a PDF: controls, themes, rotation, position restoration and close/reopen.
3. Browse/pin a source, add a novel to Library, download a later chapter, and confirm the chapter list remains intact.
4. Switch tabs, scroll shelves, try larger system text, and verify Library sort/view survives restart.

Actual speed depends on the phone and publication; no FPS claim is made without device profiling.
