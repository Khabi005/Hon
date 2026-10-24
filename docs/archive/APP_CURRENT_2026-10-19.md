# Hon 1.1.1 — ready for phone acceptance

This is the current handover. The known remaining implementation gaps in the agreed repair/feature scope are closed. The next gate is the user's phone acceptance, followed by fixes for any problems that test reveals. Actual device smoothness and every live website have not been verified.

## Install the latest APK

[Hon 1.1.1 complete](../build/releases/Hon-1.1.1-complete.apk) is the optimized release intended to update the existing Hon installation. Install over the app and keep its data; no uninstall is required. Version name/code: **1.1.1+3**.

Use this file instead of the older 1.1.0 APK. A separately signed production APK is retained for future distribution; it cannot update the existing local-certificate installation. See [release instructions](RELEASE_GUIDE.md).

## Verified release files

| Build | Bytes | SHA-256 |
| --- | ---: | --- |
| Update-compatible complete APK | 75,345,628 | `430facc18d4cf97a252edee4ac3c204617f5de04f47b09cb8dde3adefd3a72a8` |
| Dedicated-key production APK | 75,425,687 | `328dad2a8615857d24c0be7fe07a49d7c507422ea71535b7792f645f94730946` |

Both signatures and matching app payloads were verified. The complete APK retains the existing local certificate. Both APKs are non-debuggable release builds with all 172 source hashes and eight text fonts verified. The Android 13 compiled adaptive icon points to the packaged transparent monochrome mask, verified against the supplied artwork. Checksum sidecars and JSON verification reports accompany the APKs.

## Closed gaps

- **Reading History:** Home has a direct History shortcut and a See All action beside Continue Reading. History lists every saved read book, including finished books and novels outside Library, in most-recently-read order. Search title/author, filter All/In Progress/Finished, view date groups and saved progress, and tap to resume with the existing reader position restoration. This is a book history based on the last saved read time, not a newly invented log of past reading sessions.
- **Library independence:** marking an outside-library book finished does not silently add it to Library. History survives database reloads and refreshes after saved progress changes.
- **Themed launcher icon:** Android 13+ adaptive icon resources now reference the existing transparent monochrome Hon artwork. Compatible launchers can tint its alpha mask with the user's wallpaper theme. Android 8–12 retain the existing adaptive icon and older devices retain their density-specific launcher icons. The supplied PNG artwork is reused directly rather than claiming it was converted into a vector.

## A fuller Home

- Warm parchment/ink discovery card with the actual enabled-source count, Browse Sources and Library Updates actions.
- Continue Reading, recent library additions and Ready Offline shelves retain real books and progress.
- Direct Library and History cards give the empty state useful destinations.
- Daily goal includes a seven-day activity chart using recorded reading minutes. Days without recorded minutes stay empty.
- Coordinated light/dark treatments; corrected Continue Reading spacing on narrow screens with larger text.
- No Home network requests, rotating background animations or synthetic popular-book results were added.

## Verification

- **8 focused checks passed** for persisted history including finished/non-library books, title/author search, filters, updates after progress saves, Home navigation, large text and the existing library/download/reader UI regressions.
- Static analysis: clean.
- Seven local fixture previews rendered without Flutter exceptions: populated Home light/dark, narrow large text, empty-library Home, weekly activity and History normal/large text. These are local renders, not phone captures.
- APK build/signature, version, source/font assets and compiled monochrome resources are verified with the release files. Earlier functional work and its verification remain documented in the [1.1.0 implementation report](APP_COMPLETION_2026-10-19.md).
- No automated phone test or broad live-source sweep was performed.

## Short phone check

Use the [five-item feature checklist](APP_COMPLETION_2026-10-19.md#one-short-phone-pass), then add:

1. Open History from Home. Confirm a finished book and a novel outside Library appear, search/filter, and resume one.
2. Look at Home in light/dark mode and confirm the source count, shelves and daily activity match your data.
3. On Android 13+ with a compatible launcher, enable themed icons and check Hon's kanji mask. Launcher support remains a device acceptance item.

## Local previews

[Home light](home-history-previews/home-light.png) · [Home dark](home-history-previews/home-dark.png) · [Empty Home](home-history-previews/home-empty.png) · [Larger text](home-history-previews/home-large.png) · [Weekly reading](home-history-previews/home-week.png) · [History](home-history-previews/history.png) · [History with larger text](home-history-previews/history-large.png)
