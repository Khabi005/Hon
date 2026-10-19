# Hon Phase 0 implementation handover — 18 October 2026

> Superseded by [Hon 1.1.1 and current APK](APP_CURRENT_2026-10-19.md). This document records an earlier milestone.


> Superseded for the current build by [the repair/design handover](REPAIR_AND_DESIGN_HANDOVER_2026-10-18.md) and [new short release checklist](MANUAL_ACCEPTANCE_2026-10-18.md). Use the release APK linked there.

**Implementation is ready for the user's manual acceptance.** The user requested functional completion before testing and will perform the phone checks. No further phone automation or ADB work was performed in this final pass. Phase 1 remains the visual design pass using the downloaded-reader reference.

This document supersedes the historical implementation claims in PROGRESS.md. The supplied brief and later explicit user decisions remain the requirements.

## Delivered functionality

| Area | Implemented behavior |
| --- | --- |
| Readium lifecycle | Request IDs; one result for ready/error/intentional close/timeout; stale session events ignored; locator flush on pause/close; readiness-gated foreground reading time and duplicate-resume protection. Native readiness waits for content rather than merely acknowledging Activity launch. |
| EPUB covers | EPUB 2/3 cover resolution and image validation; managed cover storage; backfill for existing imports; image-cache eviction and database notification without overwriting concurrent book edits. The supplied Lord of the Mysteries EPUB informed the repair. |
| Downloaded reading | Rich blocks in paged and scroll views, preserving nested formatting, links, images, dividers and Unicode. Measured intra-chapter pagination and continuous chapter loading. Semantic block/text anchors preserve positions through reflow; explicit chapter selection is not overridden by an older locator. Missing online chapters load with retry; downloaded chapters open from disk. |
| EPUB scrolling | A vertical viewport holds the current Readium resource and adjacent resources, with a maximum of three navigators. Resource documents, publisher CSS, images, links and native selection remain intact. Resources are added/removed as reading advances. Text selectors/offsets and progression restore anchors after mode switches, font changes and rotation. Fixed-layout publications retain native pagination. A resource load failure or excessive continuous chapter height falls back visibly to Paged mode. This replaces the earlier boundary-gesture workaround. |
| EPUB tools | Six theme colors, native selected-quote sharing with attribution, durable chapter bookmarks, rotation reflow, current-orientation lock/unlock, publisher-formatting option and shared saved appearance preferences. |
| Search/settings | Enabled-source global search with debounce, grouped loading/error/empty/retry states; source-qualified results; repository management; reader appearance settings; accurate metadata-archive wording and accessible open-source notices. |
| Repository lifecycle | HTTPS repository/index URLs; persisted catalog; install/update/enable/disable/uninstall; checksum and API checks; recursive static Require dependencies including nested helpers and minimum versions; atomic replacement with recovery journal. Browse and background downloads use the same installed bundle. |
| Extension host | Safe core Shosetsu 1.x model, collection, DOM, request/form/header, listing and passage APIs. Original upstream standard Lua helpers are packaged with notices. Zero-based app pages are translated to source startIndex. WordPress, Bixbox and Madara fixtures execute with shared libraries. Unknown modules/APIs fail visibly. Java reflection, files, processes and dynamic loaders are unavailable to scripts; instruction/time/allocation and network budgets constrain execution. |
| Downloads/data | Unique WorkManager jobs; no raw-HTTP fallback for missing scripts; transactional chapter/job completion; cancellation guards; managed-path checks; atomic chapter replacement and previous-file recovery. Downloaded HTML embeds chapter images within size/count limits. Migration failures stay visible/retryable; resume refreshes durable worker state; library membership remains independent of downloads. |

## Verification and limits

- Final focused Flutter checks: **22 passed** across installed dependencies, repository lifecycle, native-reader session handling, rich pagination and preference persistence. Final static analysis: **no issues**.
- Final Kotlin JVM checks: **15 passed**, zero failures/errors. The debug APK built successfully, and packaged runtime helpers/licenses were checked. Native fixture checks use exact upstream scripts with deterministic offline website responses; they do not establish that a remote website is currently reachable or unchanged.
- Prior repair batches passed broader local checks (61-test baseline, then focused durability and reader checks). These are historical results, not a claim that every suite was rerun for this final build.
- An earlier APK was checked on the connected Android 16 phone: the supplied EPUB had a cover and opened/closed after more than 18 seconds without the old late notice. **The new continuous viewport and final APK still require the user's device acceptance.** No device success is inferred from compilation or JVM tests.
- The host supports compatible Shosetsu core contracts; it does not promise every extension, unrestricted Java interoperability, anti-bot bypasses, or parity with every upstream Kotlin API. Unsupported capabilities produce errors. The three-resource viewport bounds the navigator count, not the size of an individual publisher chapter.
- PDF remains rendered by pdfx with page/zoom/bookmark behavior. Selectable PDF quote extraction is unavailable and is not advertised.
- Native EPUB and downloaded-reader controls still differ visually. Detailed visual unification belongs to the user's Phase 1 design pass; original EPUB content was not replaced with stripped text.
- Chapter files downloaded before image embedding must be downloaded again to gain embedded offline images.
- The pre-existing hon_review.xml changes and hon_review antigravitities.xml file were left untouched. No database reset, remote push, or phone-data export was performed.

## Build and acceptance

APK: `build/app/outputs/flutter-apk/app-debug.apk` (project's existing debug signing key). Install over the existing app. The older release APK is not the final handover build.

Final debug build succeeded. SHA-256: `28da384ada7bea32614a39f243ea66626e77f86eb1d6e20d693c892fc24e322b`. APK size: 213.0 MiB.

Use [the short manual checklist](PHASE0_MANUAL_CHECKLIST.md). Phase 0 implementation is delivered for acceptance; functional acceptance remains pending those phone results. Phase 1 visual work has not started.

## Upstream provenance

Original helpers and license: `android/app/src/main/resources/shosetsu/`; exact source fixtures and provenance: `android/app/src/test/resources/shosetsu/`. Notices include source URLs and snapshot hashes. Settings → Open-source licenses also exposes the packaged helper license.

References inspected during implementation: [Shosetsu kotlin-lib](https://gitlab.com/shosetsuorg/kotlin-lib) and [N4O extensions](https://github.com/noaione/shosetsu-extensions), including WordPress/Bixbox/Madara shared-library and dependency conventions.
