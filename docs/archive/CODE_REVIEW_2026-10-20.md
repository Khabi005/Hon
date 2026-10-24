# Hon: current-code review and implementation handoff

Reviewed 20 October 2026. Scope: source inspection of sources/installations, reader preferences/highlights/bookmarks, reconciliation, backup, images, and the requested UI. No tests, builds, device operations, or application edits were performed. This is not a certification of the whole app or of the installed APK.

The older review is historical context. Several of its findings now have partial or substantial implementations; do not blindly reapply old fixes.

## What is implemented

- Dark glass backdrop is solid black. The large gradient wash has been removed from that component.
- Bottom navigation has real clipped backdrop blur, semantic labels, reduced-animation handling, and a high-contrast fallback. The requested moving glass animation is still absent.
- Home uses a smaller Continue Reading heading/card and hides `---` and `Unknown` authors. It remains a heading above a carousel, rather than a newly grouped resume-reading section.
- Flutter reader highlight background spans and note cards exist. Actual selection capture remains incorrect.
- Native EPUB highlight actions, Readium decorations (including the continuous path), notes, Contents entries, locator bookmark payloads, and per-book preference bridge methods exist.
- Snapshot export/import includes SQL collection names, and library writes synchronize membership rows. Legacy preference-based collection import now calls the database service.
- Backup extraction rewrites managed image paths inside chapter files. This addresses the previously entirely missing relocation step, with caveats below.
- Catalog hashing and merging new host declarations into installed sources exist.
- Source error UI presents a readable message and expandable technical details.
- Image processing now restricts header MIME types and considers decoded pixel count. Output MIME correctness and decode failures remain incomplete.

## Confirmed defects and unmet requirements

### 1. P1 — Chapter matching can still reuse an unrelated download

`lib/core/updates/chapter_update_service.dart:225–274`

The exact-title fallback checks uniqueness only among remaining OLD chapters, not among incoming chapters. The third pass checks index and fuzzy title similarity. Since chapter indices are normally unique already, its `matchingOld.length == 1` adds little protection.

For example, an old “The red door” and a replacement “The blue door” at the same index satisfy the current 0.5 token-overlap threshold. The old file and download state are then preserved by `copyWith`. Matching blank/non-Latin titles is also problematic because normalization removes non-ASCII characters.

The new `repairedIdMap[matchedOld.id] = chapter.id` records the same local ID on both sides; `sourceChapterId` is not updated in the matched branch.

Implement: stable upstream identities and explicit aliases; reject ambiguous matches on both sides. Do not use fuzzy title/index matching to transfer downloaded content. Preserve unresolved old downloads separately and keep progress attached to stable local identities.

### 2. P1 — Native per-book changes also write global preferences

`android/app/src/main/kotlin/com/hon/reader/hon/ReadiumReaderActivity.kt:899`
`android/app/src/main/kotlin/com/hon/reader/hon/HonReaderBridge.kt:135`
`lib/app/hon_app.dart:26`
`lib/app/bootstrap/providers.dart:120–143`

Native `saveDurablePreferences` both saves a per-book row and sends `reportPreferences`. That event has no book ID/scope. HonApp routes it into the shared preference notifier; normal native EPUB opening does not set that notifier's active book, so it writes global preferences. A book-specific change can change other books' defaults.

Implement: explicit preference scope and book identity end-to-end. Applying/loading book settings must not silently persist them as global defaults.

### 3. P1/P2 — Preference persistence and reset are still inconsistent

`lib/app/bootstrap/providers.dart:93,120,131,239`
`lib/features/reader/sheets/themes_settings_sheet.dart:282`
`android/app/src/main/kotlin/com/hon/reader/hon/ReadiumReaderActivity.kt:1490,1531`

- Queued `_persist(next)` reads mutable `_activeBookId` when the job executes, rather than capturing its intended destination when queued. Closing/switching a reader can redirect a pending write.
- `reloadDefaults()` does not first reset state. If there is no saved global preference string, `_load()` returns with the previous book's state still active.
- Flutter Reset calls `reloadDefaults()`, which clears the active book ID, without reselecting the open book afterward. Subsequent changes can write globally.
- Native Reset still hardcodes Calm, size 1.0, and paginated mode. It removes the override but does not apply current global defaults.
- Flutter overrides use `size/layout/font/...`; native overrides use `fontSize/isScroll/typography`. Readers do not consistently translate both representations, particularly when opening a native EPUB in the Flutter preview.

Implement: one versioned preference model, capture destination alongside each queued write, separate stored global defaults from effective book state, and make Reset apply globals while retaining the open book's editing scope.

### 4. P1/P2 — Extension installation/update loses necessary permissions

`lib/core/sources/installed_extension_service.dart:263–305`

Repository installation still calls `validateExtension(bundle)` without the extra allowed hosts. Sources requiring an external bootstrap host can fail before installation. After validation, the new installed record initializes permissions from the repository host only, discarding the prior record's configured hosts. It also defaults to enabled instead of preserving a disabled update target.

Implement: resolve authorized source capabilities before validation; pass them into validation and runtime, preserve user permissions and enabled state on updates, and do not grant repository/image domains merely because they appear in unrelated metadata. Explicit bundled reinstall is a different path and does not prove repository installation works.

### 5. P2 — Catalog upgrades resurrect deliberately uninstalled sources

`lib/core/sources/bundled_source_catalog.dart:42–58`
`lib/core/sources/installed_extension_service.dart:332–408,466`

Hash changes rerun seeding across the entire catalog. Uninstall removes the installed record without a persisted removal marker. Seeding treats each absent record as a new installation. The claim that upgrades preserve deliberate removals is therefore incorrect.

Implement: persistent removal choices and separate first-install/new-source/permission-migration paths. Preserve disabled sources. Keep explicit user-requested reinstall possible.

### 6. P2 — Highlight location is inferred, not captured

`lib/features/reader/presentation/reader_screen.dart:547–605`

The selection handler retains only text. Saving searches blocks from the beginning using `indexOf(text)`. Repeated passages select the first occurrence. A cross-paragraph selection falls back to a matching prefix and the end of one block; if no match is found, it still uses the viewport anchor. The stored range is consequently not reliable.

Implement: capture the actual selected chapter/block/range, support multi-block selections, and render/navigate all selected spans. Store stable chapter identity and recovery context. The current span-rendering tests do not exercise this selection algorithm.

### 7. P2 — Image conversion still labels converted PNG bytes as WebP/GIF

`android/app/src/main/kotlin/com/hon/reader/hon/OfflineChapterImages.kt:37–76,130–158`

Resizing a non-JPEG image encodes PNG bytes, but filename extension/data-URI MIME still use the original type. Invalid decode dimensions, failed decoding, and caught `Throwable` return original bytes as if conversion succeeded; a whitelisted header alone can still admit corrupt content.

Implement: return validated bytes with their actual output format/MIME. Reject invalid decodes through the existing graceful missing-image path. Keep the new pixel bounds; do not fall back to accepting an invalid or unsafe original after a processing failure.

### 8. P2 — Requested liquid-glass interaction is absent

`lib/app/navigation/tab_scaffold.dart:89–139`
`lib/app/theme/glass_surface.dart:41–55`

The navigation is a row of separate `AnimatedContainer`s using `easeOutCubic`; each item's fill changes in place. There is no shared moving selection capsule, spring motion, deformation, or press/drag interaction. Default glass uses 80–94% opaque surface tint, which also makes the blur subtle. Default non-navigation surfaces are solid by the component's condition.

Implement: one moving glass indicator with spring motion and press feedback, readable labels, reduced-motion behavior, and visibly translucent but restrained default glass. Keep black backgrounds and bounded blur. Stronger glass should increase material treatment, not restore colored background haze.

### 9. P2 — Home and customization work is partial

`lib/features/home/presentation/home_screen.dart:141`
`lib/features/home/presentation/widgets/continue_reading_card.dart`
`lib/features/reader/sheets/themes_settings_sheet.dart`
`android/app/src/main/kotlin/com/hon/reader/hon/ReadiumReaderActivity.kt:1486–1546`

Continue Reading retains the separate heading/carousel arrangement; its dimensions changed. “Unknown Author” is not included in the card's placeholder filter. Native Customize still has a list of full-width font buttons and multiple sliders/switches. Smaller cards alone do not establish the compact reference layout or visual parity between readers.

Implement the grouped resume-reading section and compact reference-led appearance controls after correctness fixes. Preserve working controls and touch targets. The current code contains cream colors, serif font mappings, and italics support, but visual fidelity and smoothness require observing the rendered result; source inspection cannot certify those.

## Improved areas with remaining caveats

### Backup

Image relocation and SQL collection restore are now implemented. However:

- `backup_service.dart:524–550` rewrites raw strings across whole chapter files, scans every restored image for every chapter, and silently swallows rewrite errors. Prefer parsed image attributes and a direct lookup; surface failures rather than reporting an entirely successful restore with broken images.
- Legacy collection import calls `createCollection(name, id)`. `database_service.dart:108–121` may return an existing same-name collection with a different ID without remapping imported memberships. A legacy backup's collection can still become orphaned when the destination already has the same name under another ID.

### EPUB bookmarks

Locators are now saved and used to navigate. However, `database_service.dart:1976` still toggles bookmark identity by book plus `pageIndex`; native passes a chapter index. Bookmarking another position in the same chapter removes the existing bookmark. Decide/document this limitation or use locator-based bookmark identity for multiple positions.

### Source certificate handling

The app bundles a certificate whose local metadata identifies subject `ISRG Root YR`, issuer `ISRG Root X1`, and validity May 2026–September 2032. The custom trust manager and network-security XML include it; the inspected code does not use a trust-all manager or a hostname-verification bypass.

This establishes the implementation, not that it fixes the phone's failing endpoint. It is installed as an app-wide trust anchor, rather than scoped to one source. Confirm certificate provenance, intended scope, and the actual failure chain before declaring SSL resolved. Do not add more certificates speculatively or weaken verification. No live endpoint investigation was performed in this review.

## Remaining implementation and work order

1. Correct chapter identity and preference scope/persistence first.
2. Complete installation/update permissions, deliberate removal handling, and evidence-based source connection diagnosis.
3. Complete true highlight ranges, reset semantics, image format handling, and legacy restore edge cases.
4. Finish the requested glass interaction, grouped Home resume section, compact customization, and reader visual consistency using the supplied references.
5. Scheduled background chapter checks still have no periodic scheduling implementation in the inspected application source. Implement the previously discussed capability with an opt-in setting, bounded work, cancellation, and useful status if it remains part of the release scope.
6. Finally perform focused verification of changed behavior and produce one update-compatible optimized APK. Let the user do broad phone testing. CI and removing the host-only Dart engine are lower-priority engineering follow-ups, not substitutes for these fixes.

Do not erase app data or restart from scratch. Treat existing completion reports as historical claims. For every task, distinguish implemented code, focused verification, phone verification, and external blockers.
