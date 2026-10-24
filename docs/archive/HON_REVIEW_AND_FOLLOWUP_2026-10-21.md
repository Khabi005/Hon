# Hon — implementation review and Antigravity follow-up

Date: 21 October 2026

## Verdict

**Substantial progress, but the claim that all seven subphases are complete is not supported by the current code.** Several features are present, several are partially connected, and there are remaining functional bugs. This is more than a final phone-testing checklist.

This review inspected the local working tree, including Antigravity's uncommitted changes, against the supplied October 20 audit, implementation report, project-brief material and latest user requirements. It is a targeted static review, not an exhaustive certification of every feature. No tests, builds or phone checks were run. The local tree is the evidence; this review does not claim it matches the published GitHub version.

The overall architecture still follows the brief: local books, independent library membership and downloads, source browsing, EPUB/PDF support, persistent reading state, and Apple Books-inspired controls. The user's newer requirements supersede older design choices, particularly solid backgrounds, separate Standard/Liquid Glass modes, and EPUB export.

### Updated distribution requirement — 21 October 2026

**Latest clarification: finish the full app with its current bundled repositories/extensions first. Keep the existing bundling and seeding behavior during this work.** Complete the functional repairs, reader features, UI and polish before making distribution changes.

The user-added-repositories-only release and separate Google Play edition are **deferred follow-up work after the whole app is finished**, not part of the current implementation pass. Sections F and G retain those future plans for reference; do not remove bundled repositories, introduce release variants or change application IDs now. Preserve existing user data throughout.

Support Shosetsu repositories through the compatible engine. LNReader repositories must only be offered as supported after their format and extension runtime are actually integrated; accepting a URL alone does not provide compatibility. Clearly explain unsupported repository formats.

## What really improved

| Area | Current evidence | Status |
| --- | --- | --- |
| Chapter/job ID handling | Catalogue and reader Contents use `resumeDownloadForChapter`; manager resolves the associated job | Implemented in inspected call paths |
| Bulk actions | Selection mode and selected download/delete actions exist in both Flutter catalogues | Implemented, with remaining omissions below |
| Next chapter presets | 5, 10, **15**, 25 exist; coordinator excludes active/paused jobs before taking N | Implemented in inspected paths |
| Add to Library | Coordinator queues first, then invokes the existing prompt | Connected for coordinator download paths |
| Deletion failures | Structured result; file deletion failures retain chapter metadata; managed-path checks added | Improved, cancellation still unsafe |
| Library navigation | Web novels default to catalogue; preference permits direct reader opening | Implemented |
| Cached catalogue | Cached book/chapters displayed before refresh; refresh failures can show a banner | Implemented, current-chapter positioning incomplete |
| Download status | Reader Contents listens to database changes and has state-specific indicators | Implemented, batch notification refresh is broken |
| EPUB fullscreen | Native bars now use `GONE`; system bars are hidden; locator restoration requested | Code fix present; actual insets/reflow need phone verification |
| Brightness controls | Flutter and native System/Custom controls exist | Persistence and default bugs remain |
| Reader appearance | Flutter header/footer have rich-mode blur; native accepts an appearance argument | Native setting key is wrong; sheets remain incomplete |
| EPUB export | ZIP/package/nav/spine/chapter generation and menu entries exist | Incomplete user flow and resource handling |
| Title normalization | `ChapterUpdateService.normalizeTitle` uses `replaceAllMapped` | Prior literal `$1` bug addressed |
| Source diagnostics | Error classification and a capability model exist | Does not prove individual capabilities work |

## Remaining findings, ordered by practical priority

### 1. Cancellation is acknowledged before the worker stops — high priority

`HonDownloadManagerBridge.kt:48` schedules cancellation on an executor. Its method-channel handler at approximately line 237 immediately reports success. Consequently Dart's awaited cancellation is not an acknowledgement that native cancellation, token invalidation, or `stopAndAwait` finished.

`database_service.dart:1966` awaits that hook before deleting files, but can proceed while the worker still writes. It also catches cancellation failure and continues deletion. Pause followed quickly by Resume has the same ordering risk: delayed cancellation can interfere with a newly scheduled attempt.

**Fix:** complete the method-channel result only after cancellation is durably applied and the target attempt stops; report errors. Coordinate replacement/resume under the same per-job ordering. Abort destructive file deletion for a target whose cancellation failed. Preserve chapter progress and library membership.

### 2. Batch notification actions leave the Flutter queue stale — high priority

`HonDownloadManagerBridge.kt:103` emits `notifyStateChanged(bookId, "ALL", ...)`. `hon_download_manager.dart:297` treats every nonempty job ID as one real job and calls `refreshDownloadJob("ALL")`. `database_service.dart:1044` finds no such row and returns without refreshing the affected jobs/chapters.

**Fix:** introduce an explicit batch event, or omit the job ID and refresh the affected book/all jobs. Do not overload an ID with a sentinel that the receiver does not understand.

Batch cancellation also enumerates process-local `schedulingLocks.keys` to cancel WorkManager jobs. That is not a durable inventory after process recreation. Read the affected job IDs from SQLite and cancel their durable work, including invalidating the corresponding attempts. Serialize batch actions against concurrent enqueue/resume and define the paused/cancelled scope explicitly.

### 3. The single notification is not yet an aggregate queue controller

`DownloadNotifications.kt:17` gives each chapter worker the same notification ID. `HonDownloadWorker.kt:89` publishes it before the request gate, so a waiting worker can replace the displayed title of the worker actually downloading. The only call supplies no measured progress; there is no continuing notification update as passage/images advance or the queue changes.

Sharing one ID does not establish coherent ownership or lifecycle. AndroidX manages foreground information per worker and removes notifications as workers finish, making this design require particular care. See the [AndroidX foreground dispatcher implementation](https://raw.githubusercontent.com/androidx/androidx/androidx-main/work/work-runtime/src/main/java/androidx/work/impl/foreground/SystemForegroundDispatcher.java).

**Fix:** use a queue-level foreground owner/controller with durable aggregate state. Show the active chapter(s), waiting count, and truthful determinate or indeterminate progress. Ensure one worker completing cannot retire the ongoing queue notification. Support clearly scoped Pause/Resume/Cancel and dismiss when the aggregate work actually ends. Android system notifications remain Android-rendered; Cupertino styling applies to in-app banners and controls.

### 4. System brightness is not the default and does not reliably survive restoration

`reader_theme.dart:170` still defaults to `0.85`. At line 282, `fromMap` clamps any saved value to `0.1..1.0`, turning the System sentinel `-1` into `0.1`. `providers.dart:240` applies the same clamp to native typography updates. Book settings are restored through `fromMap`.

**Fix:** model System/Custom explicitly or consistently preserve `-1` in every serializer, native event, book override and reset path. New defaults must follow the system. Define migration for the old implicit 85% default without discarding deliberate custom settings. Apply this to EPUB, downloaded/online readers and PDF, and release overrides on reader exit.

### 5. EPUB reads the wrong appearance key

`app/theme/app_appearance.dart:6` saves `hon_app_appearance_v1`, but `reader_navigator.dart:95` reads `hon_app_appearance`. Under the current settings path, selecting Liquid Glass therefore still sends `isGlass: false` to the native reader.

**Fix:** use the shared constant/provider and wait for the persisted setting if necessary. Avoid duplicate string literals for preference keys.

### 6. Glass and reader parity are still partial

Flutter header/footer have rich-mode blur, but `reader_menu_popup.dart:150`, `reader_contents_sheet.dart:201`, and `themes_settings_sheet.dart:54` still build solid surfaces without an appearance branch. The themes sheet also replaces the inherited Theme with a base theme, losing the appearance extension. Native glass currently changes the bar color's alpha to 82%; that alone is not equivalent to the requested glass material or Flutter backdrop blur.

The reader's top-left action is now **previous chapter** (`reader_screen.dart:1769` and native `ReadiumReaderActivity.kt:706`). The user requested a route back to the novel catalogue, with reload moved to the bottom controls. Changing both readers to previous-chapter behavior does not fulfill that request.

**Fix:** create a shared visual specification for menu dimensions, icons, spacing, typography and actions across Flutter/native readers. Standard reader surfaces stay solid. Liquid Glass applies to chrome, Contents, settings and popups, with readable contrast and reduced-motion/high-contrast fallbacks; the reading page stays solid. Use consistent catalogue/back behavior for web novels and a clear Contents action for imported books. Preserve a separate close action and use a real icon system rather than inconsistent text glyphs.

### 7. Current-chapter scrolling still guesses positions

`source_catalog_screen.dart:758` assumes a 440-pixel header and 56-pixel rows; `reader_contents_sheet.dart:83` assumes 54-pixel rows. Actual headers vary with synopsis length, banners and text scale, and chapter titles wrap. Catalogue auto-jump is scheduled after a successful network response, not after cached chapters first appear, so offline opening does not reliably satisfy this requirement.

**Fix:** locate the actual chapter by stable ID and use an indexed list or measured/keyed row positioning. Handle display sorting, long titles, text scaling and cached/offline entry. Perform the initial jump once after data/layout are ready, without repeatedly stealing the user's position on refresh.

### 8. EPUB export is not yet a complete portable export

`epub_export_service.dart:31` reads only currently loaded chapters unless given a list. The Library action at `library_screen.dart:599` does not load them first. A freshly opened app can therefore report no downloads even when SQLite contains them.

The exporter writes to the application's private `exports` directory, and both UI callers only show a path in a snackbar. There is no Save As or Share action, so the user has no normal way to obtain the file.

The native downloader stores illustrations as `file:` URLs (`OfflineChapterImages.kt:185`). Export retains those URLs but does not bundle chapter image files or rewrite their references into the archive. An exported book containing these illustrations is not portable. Remote cover URLs are also skipped because the cover branch only checks a local `File`.

The `toValidXhtml` helper only patches three void elements with regex; it is not a general XML serialization/validation step. Export accumulates all content in memory and synchronously ZIP-encodes it on the caller's isolate. Read/write exceptions escape the result API and the UI actions lack a surrounding catch.

**Fix:** hydrate chapters from SQLite; capture a consistent export snapshot; package supported illustrations/cover with correct media types and relative references; serialize valid XHTML; use a cancellable background task or streaming approach for large series; write atomically to a temporary output; provide Android Save As and Share. Report missing chapters/images and I/O failures clearly. Do not label an EPUB fully validated based only on ZIP entries and string checks.

### 9. The new ad sanitizer is only used by export, and its rules can remove real content

The production references to `ChapterContentSanitizer.sanitize` are in the EPUB exporter. The normal download worker still fetches passage HTML, embeds images, and saves it without this sanitizer. Therefore this addition does not remove the reported ads from normal downloaded reading.

The sanitizer uses broad substring matches, including `translated by`, and deletes short matching paragraphs. A legitimate passage such as `<p>The inscription was translated by the old monk.</p>` matches that rule. Matching class/id fragments can also remove whole containers. The unused `chapterTitle` argument does not remove duplicate chapter headings.

**Fix:** use conservative DOM/source-specific rules in the actual passage pipeline and an optional safe cleanup path for existing downloads. Preserve narrative, illustrations, attribution and translator notes unless explicitly unwanted. Do not apply the present broad rules globally. Remove duplicate headings only with strong title/context matching. Restrict URL schemes in exported links/resources and serialize their text safely.

### 10. Diagnostics claim success for operations they never perform

`SourceHealthService.testSource` makes one empty-query/listing-0 call. `diagnoseSource` then marks Novel Parsing and Passage Fetching operational whenever that call succeeds, without fetching a novel or passage. Search support metadata is also conflated with successful search execution.

**Fix:** separate Supported, Not tested, Working, Empty and Failed. Probe actual stages only when a diagnostic is requested, with bounds on requests and time. Include source/version/operation and useful error details. Do not mark every source repaired from the existence of this service. Preserve working sources; use representative failing cases to distinguish TLS, host policy, changed selectors, authentication and site outages. Do not disable TLS verification to obtain a green result.

LNReader can be a functional reference and a source of compatible, licensed adaptations. Its [repository](https://github.com/LNReader/lnreader) uses React Native; do not assume its extensions can simply run in Hon's Lua engine. Review each adapter's dependencies and license, and preserve existing source/book/chapter identities or supply a migration.

### 11. Bulk features still miss explicit requirements

Both catalogues expose **Delete read** and **Delete all**, but the requested explicit **Delete unread downloaded chapters** action is absent. Reader Contents offers the four next-N presets but no custom-N action. Individual selection is useful but is not a substitute for those requested actions.

**Fix:** add custom N and explicit delete-unread selection with a preview/count and confirmation. Distinguish current, read and unread using the application's defined reading state; never delete merely because a displayed index shifted. Keep progress, bookmarks, highlights and library membership.

### 12. Missing local files cannot be reconciled through the new deletion path

`StorageService.isPathInsideManagedStorage` at line 34 returns false when the file does not exist. `deleteDownloadedChapters` uses that check before its existence check, so a stale path inside managed storage is reported as an unsafe deletion and retained indefinitely.

**Fix:** distinguish absent-but-valid managed destinations from existing unsafe paths. Reconcile a genuinely missing chapter file to not-downloaded without deleting anything. Keep canonical/symlink protections for existing files and validate against chapter storage specifically. Reclaim shared images only when unreferenced; do not remove another chapter's illustrations.

## What the verification report actually establishes

The supplied report says 21 targeted Dart tests passed and analysis found 0 errors. I have not rerun those commands.

The current five `reader_preferences_test.dart` tests cover font/theme persistence and scope; none asserts system-brightness default or `-1` round-tripping. The EPUB test checks archive entries and strings but does not assert the ZIP compression method or parse every output as valid XML. The deletion test replaces native cancellation with an immediately completing callback, so it cannot establish real worker shutdown ordering. Those tests are useful but narrower than the report's completion claims. Flutter analysis does not compile the modified Kotlin code.

## Follow-up prompt for Antigravity

Implement the remaining Hon fixes below in the existing working tree. Read the findings above as review evidence, confirm them against current code, and preserve already-working changes. Do not restart the implementation or rewrite the app. Treat the latest user requirements as authoritative over older brief choices.

### Working order and constraints

1. Fix functionality and state consistency first; finish UI afterward. The user will perform the main phone testing.
2. Keep work incremental and preserve library membership, chapter identities, downloads, reading positions, bookmarks, highlights and per-book settings.
3. Do not call a feature complete merely because a class, menu, test, or diagnostic model exists. Trace the actual UI → Dart → native → storage → UI path.
4. Avoid repeated broad tests, builds and live all-source sweeps. At the end, run one focused verification pass covering changed behavior plus the necessary native compile check; report exact commands/results and leave subjective visuals/device behavior on a short user checklist.

### A. Download state and deletion

- Return native cancellation acknowledgement only after durable status/token updates and worker shutdown; surface failures to Dart. Serialize rapid Pause/Resume and cancellation/replacement. Never delete a chapter file when cancellation failed.
- Repair batch notification events so Flutter refreshes the actual affected chapters/jobs. Use durable IDs when stopping jobs after process recreation.
- Replace the per-worker notification overwrite approach with one coherent queue notification lifecycle. Include current activity, waiting count, truthful progress and queue controls; keep it alive while work remains.
- Reconcile missing managed chapter files safely. Preserve failed deletions for retry. Clean up unreferenced illustration files safely.
- Retain the correct chapter-to-job lookup and shared coordinator. Add explicit Delete unread downloads and custom next-N in reader Contents. Ensure bulk actions in both catalogues use the same queue/library-prompt rules.

### B. Reader settings and navigation

- Make System brightness the default and preserve it across global/book serialization, native callbacks, reset, reopening and PDF. Do not clamp the System sentinel into a custom value.
- Read appearance through the existing shared `appAppearanceKey`/provider, not the incorrect unversioned key.
- Keep Library's catalogue default and Home's direct Continue action. Make cached catalogue data useful without a successful network refresh.
- Jump to the actual current chapter by stable identity with correct layout positioning; support long lists, sorting, long titles and text scaling.
- Implement the requested catalogue/back action in web-novel reader chrome, move reload to lower controls, and maintain unambiguous close/Contents actions for other formats.
- Preserve the `GONE`/immersive fullscreen fix and verify locator restoration without resetting reading progress.

### C. Real EPUB export and passage cleanup

- Export from durably loaded downloaded chapters, ordered correctly, without requiring the user to open the catalogue first.
- Package cover and chapter illustrations, rewrite local/data references to archive resources, generate valid XML/XHTML and correct metadata, and report omitted material.
- Export large series without blocking the UI or holding unnecessary duplicate content in memory. Handle cancellation and I/O errors; finalize atomically.
- Add Save As and Share through Android's normal file mechanisms. A private file path snackbar is insufficient.
- Connect conservative ad/duplicate-heading cleanup to the actual downloaded/online passage pipeline. Protect prose, formatting, illustrations and legitimate attribution; do not use the present broad `translated by` rule globally.

### D. Sources and honest diagnostics

- Preserve working sources. Repair demonstrated source failures based on the failing operation and error evidence.
- Represent untested stages as Not tested. Do not infer passage fetching, novel parsing or search success from one empty-query catalogue call.
- Permit bounded diagnostics and compatible LNReader/other adapters after checking runtime, license and identity migration. Never bypass certificate validation.

### E. UI after functionality

- Keep Hon's black dark background and established six reader themes.
- Standard app mode retains subtle visible glass on navigation; Standard reader surfaces stay solid.
- Liquid Glass mode should be clearly richer in navigation, reader chrome, popups, Contents and settings, with bounded blur, highlights and responsive motion. Keep prose backgrounds solid and controls readable; honor accessibility settings.
- Match EPUB and downloaded-reader control layout, icon vocabulary, spacing and interactions. Keep compact customization sheets. Preserve appearance extensions when nesting themes.
- Reduce avoidable whole-list rebuilds for per-job progress, avoid synchronous filesystem work during UI actions, and keep long catalogues lazy. Optimize specific expensive paths instead of adding effects everywhere.

### F. Deferred follow-up after the full app is finished: user-added repositories only

**Not part of the current pass. Keep bundled repositories/extensions as they are while completing sections A–E.** The following describes the later distribution change.

- Complete source/extension functionality before changing distribution defaults.
- For a fresh install of the final build, ship no installed/bundled extensions, no preconfigured repositories, and no automatic source installation or repository fetching. Remove release startup/recovery paths that silently restore bundled sources.
- Provide a clear empty Browse state with an Add repository action and repository/extension management in Settings. Online features become available after the user explicitly adds a supported repository and installs extensions. Local imports require no repository.
- Keep development fixtures/configuration separate from release defaults. Preserve explicitly user-added repositories/extensions and existing reading data on upgrades; define the migration of legacy auto-seeded sources before removing their records.
- Verify the user-added repository flow: add repository, inspect available extensions, install, browse/search, read/download, update, uninstall and reinstall. Offer LNReader compatibility only when its repository format and runtime have actually been implemented.

### G. Deferred follow-up after the full app is finished: separate Google Play edition

The user additionally requests a second edition for Google Play, after the entire full app is finished, including UI and polish. Do not create this edition during the current pass. For that later work, keep one shared codebase with explicit build variants rather than two diverging copies:

| Edition | Intended distribution | Source/extension behavior |
| --- | --- | --- |
| Full edition | GitHub | Engine and repository management available; fresh installs have no repositories or extensions until the user adds them |
| Local reader edition | Google Play | Local EPUB/PDF library and reader; no source browsing, online search, repository management, extension installation/runtime or source-download workers |

- Exclude source/extension functionality and its unnecessary native dependencies, assets, services, receivers and permissions from the Play artifact at build time. Hiding tabs alone is insufficient. Preserve the reading engine and components genuinely required for local reading.
- Adapt Home, tabs, Search, Settings and empty states to the local-reader scope, removing dead online actions. Retain themes, accessibility, local reading progress, bookmarks, highlights and applicable backup features.
- Add Settings → About → GitHub linking to `https://github.com/Khabi005/Hon`, where users can find project information and the full edition. Open the link in the browser; do not turn the Play build into an APK downloader, installer or self-updater. Review the link's presentation and destination against the policies in force at submission.
- Use distinct application IDs so both editions can coexist, preserving the current full edition's identity and data. Clearly distinguish their names/icons or edition labels. Define backup/import compatibility; never assume two application IDs share private files.
- Produce the Play edition as a separately signed/configured release AAB, with its own accurate store description, privacy/Data safety declarations and applicable release checks. Do this after source reliability and current functional/UI fixes; it must not delay those repairs.
- Do not claim that extensions are categorically forbidden or that removing them guarantees approval. Google's current Device and Network Abuse policy distinguishes downloaded executable code from interpreted code, including Lua, and still requires policy compliance. Recheck requirements before submission: https://support.google.com/googleplay/android-developer/answer/16559646?hl=en

### Completion report

Return a requirement-by-requirement table: **Implemented**, **Partially implemented**, **Blocked**, or **Needs phone verification**. For each item cite changed files and actual verification evidence. List remaining limitations plainly. Provide one small final phone checklist and an APK only after the code work and focused checks are complete. Update `docs/PROGRESS.md` so it no longer overstates completion.

Report sections F and G as **Deferred by user — after full app completion**. Their absence is not a blocker for completing the current implementation pass.
