# Hon — repair and first visual pass, 18 October 2026

> Superseded by [Hon 1.1.1 and current APK](APP_CURRENT_2026-10-19.md). This document records an earlier milestone.


> Superseded for Phase 1 UI and the current APK by [Phase 1 completion](PHASE1_COMPLETION_2026-10-18.md). This document records the earlier repair/source pass.

The user's latest phone feedback superseded the previous Phase 0 handover: repository management asserted, font choices appeared ineffective, readers differed visually, Home felt empty, and performance was poor. The user then authorized implementation through subsequent phases, requested Shosetsu sources on first install, and retained responsibility for manual phone testing.

## Delivered

### Repository reliability and first-install sources

- The add dialog owns and disposes its controllers with its route. Parent handlers check mounting after awaited navigation. Error messages replace earlier success messages immediately.
- Source lists inside repositories are lazy, searchable screens rather than eagerly constructed expansion contents. Name/language filtering and pinning make the larger Browse catalog manageable.
- Repository URLs handle GitHub tree/blob/index forms; safe dotted script names are supported. Library version metadata accepts `ver` or `version`. Script checksum verification supports current SHA-256 and older MD5 indexes.
- **172 source entries from five Shosetsu-documented repositories** are packaged offline and installed on first launch/this upgrade. Later startup respects disabled/uninstalled sources and existing repository updates. No website fetch or Lua evaluation occurs during catalog seeding. Gutenberg remains a legacy loader for saved books, and is no longer the default source list.
- Native source metadata exposes actual listing names and pagination capabilities. Empty Browse requests invoke listings rather than blindly issuing an empty text search. The catalog offers listing selection and Load more, with request-generation guards and deduplication. Unsupported text search is hidden in that source's catalog.
- Source filter/settings defaults follow the inspected upstream types, including nested groups. DOM support includes text nodes, sibling traversal, insertion of nodes/collections, and a safe `selectLast` compatibility adapter. An exact bundled RoyalRoad script is checked against offline chapter/author-note markup.
- Global Search has persistent source selection and bounded concurrency. Obsolete queries stop before launching another batch. Installing the whole catalog does not automatically query 172 websites for every typed character.

See [SOURCE_CATALOG.md](SOURCE_CATALOG.md) for snapshot provenance, packaging, upstream checksum notes and compatibility boundaries.

### Fonts and reader consistency

- Bundled Newsreader, Literata, Lora and Libre Baskerville, plus System Sans. Labels now name actual typefaces. Persisted enum identifiers are preserved for existing preferences.
- Flutter rich content and Readium use the same mapping. Readium serves bundled font assets, including italic faces and variable weights. Native typography changes synchronize back into Flutter preferences; selecting a custom EPUB font disables the publisher-typography override.
- PDF and downloaded novels share header/footer/menu widgets and the six-theme appearance sheet. Native EPUB follows the same location/close/Aa placement, menu ordering, theme grid and Customize convention. Original Readium documents and locators are retained.
- EPUB contents now uses a lazy Chapters/Bookmarks sheet; book search uses Readium's publication search service, cancelable and capped at 100 matches per query. Font controls are unavailable for fixed-layout books.
- PDF keeps page navigation, zoom and bookmarks, uses six paper/ink tone mappings and actual Android brightness/system-bar controls, and omits ineffective text-font and quote-selection controls. Opening validates and reuses the same native document instead of opening it twice.

See [READER_UI_CONTRACT.md](READER_UI_CONTRACT.md).

### Home and settings

- Home shows Continue Reading, Recently Added, Ready Offline, Library/Browse shortcuts and actual daily reading progress, with an actionable empty state. It no longer uses numbered placeholder books or an undated completion count labeled as a yearly total.
- Settings starts with actual reader/source/storage options. The oversized About banner is replaced by a compact About entry; daily reading goal is editable. Metadata export is labeled without promising a restore feature. Temporary-storage failures are visible.
- Font/source licenses and provenance are accessible through the app's license page.

### Performance work supported by code evidence

- Normal SQLite-backed saves no longer serialize the entire library/chapter/download catalog into SharedPreferences after every progress update. Legacy migration inputs are retained; explicit metadata export remains available. SQL commits and migration/recovery paths have focused regression coverage.
- Cover images decode near their display size; inactive tabs are created on demand and their tickers are disabled.
- Native continuous scroll no longer rewrites unchanged header/footer text every pixel. Locator channel events are throttled while current locators remain live and close/pause paths retain their flush behavior. Chapter indexes are cached; an idle text-anchor capture complements scrolling captures.
- Brightness and color changes no longer trigger unnecessary Flutter text-anchor/reflow work. Native brightness changes avoid publication reflow.
- Lua caches bounded immutable bytecode while keeping fresh globals, settings and execution budgets per invocation. Cache isolation is tested. Release shrinking rules preserve the public DOM/HTTP method names used by the explicit Lua capability wrapper.

These changes address identified work in the code. Phone frame times and perceived smoothness have not been measured.

## Local verification

- Focused Flutter checks passed for repository dialog cancel/add/failure transitions, first-install seeding/removal preservation, distinct real font metrics, reader preference persistence, downloaded pagination/scroll transitions, SQLite migration/durability and download recovery.
- **20 Kotlin JVM tests passed**, including the bundled source initialization/metadata probe, real WordPress/Bixbox/Madara/RoyalRoad fixtures, typed filter/settings defaults, listing pagination, cache isolation, budgets and offline images.
- The bundled probe loads **171 sources offline**; MCStories' expected offline error comes from its constructor fetching remote filter labels. Initialization/fixtures do not establish that every changing website is live or supported in every path.
- Static analysis passed. Local rendered Home light/dark, empty/populated and Flutter appearance layouts were inspected. These use test fixtures, not user data.
- The first release build succeeded. The final APK identity is recorded below after packaging the last source integration changes.
- No phone automation, ADB work, database reset, remote push, or user-data export was performed. The pre-existing review XML files were left untouched.

## Build

Final release build succeeded. Download: [`Hon-2026-10-18-reader-sources.apk`](../build/releases/Hon-2026-10-18-reader-sources.apk). Size: **70.1 MiB**. SHA-256: `183e3f27ce4bfa7baa3bbfb2964a457bba91259b1a1f87486f4c0a43baac5205`.

The release APK signature was verified and its certificate SHA-256 matched the previous debug APK: `2a33e768770e1d3b5331dbe5a450b9d21e1cbccde9f1c6aba329ead6ad9a02b7`. The application ID and existing local signing setup are retained for an update over the installed app. Older debug/release links from the previous handover are superseded. All 172 packaged source hashes, eight font assets, runtime helpers and source notices were verified inside this APK. Release shrinking retains the JavaScript height callback used by continuous EPUB scrolling.

## Remaining acceptance

Follow [MANUAL_ACCEPTANCE_2026-10-18.md](MANUAL_ACCEPTANCE_2026-10-18.md). The functional repair follow-up and initial reader/Home/settings visual pass are implemented. Device acceptance and further visual refinements await the user's observations. No claim of universal Shosetsu API/site compatibility or measured phone performance is made.
