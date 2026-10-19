# First-install source catalog

Snapshot date: 18 October 2026. The APK ships **172 source entries across five repositories**:

| Repository | Entries | Snapshot base |
| --- | ---: | --- |
| Shosetsu Universe | 60 | `https://gitlab.com/shosetsuorg/extensions/-/raw/dev/` |
| N4O | 40 | `https://raw.githubusercontent.com/noaione/shosetsu-extensions/repo/` |
| Jobobby04 | 12 | `https://jobobby04.github.io/ShosetsuExtensions/master/` |
| Suhan / Creepy Pasta | 8 | `https://raw.githubusercontent.com/creepy-pasta101/ShosetsuExtensions/main/` |
| ShosetLazy | 52 | `https://raw.githubusercontent.com/capthehacker99/ShosetLazyExtensions/master/` |

These are the repositories documented by Shosetsu, with Universe's mirror counted once. There is no finite registry of every private/custom repository; users can add more. Gutenberg is no longer the default catalog. Its loader remains for existing saved books.

## Packaging and updates

Original scripts/libraries, indexes and licenses: `third_party/shosetsu/`. Archive URLs and SHA-256 values: `PROVENANCE.json`. Rebuild packaged dependency bundles offline with `python3 tool/bundle_shosetsu_sources.py`. Bundles retain source text/comments, have per-bundle SHA-256 integrity hashes, and ship under `assets/sources/bundled/`.

First startup copies these bundles to the normal installed-extension store and saves repository metadata, without fetching websites or evaluating Lua. A persisted marker prevents later startup from reinstalling sources the user removed or re-enabling disabled sources. Existing repository updates and disabled states take precedence. Upgrade seeding preserves books/downloads.

The upstream snapshot has 41 stale checksum entries, recorded in `SNAPSHOT_NOTES.json`; bundled assets use independent hashes of the actual retained code. Online updates continue to verify supplied checksums, accepting MD5 or SHA-256 according to digest length. An invalid upstream checksum remains a visible error rather than silently bypassing verification.

## Compatibility and search

The local initialization/metadata probe loads all packaged scripts with real dependencies and no external network. 171 initialize offline; MCStories fetches remote filter labels while constructing its extension and produces an expected offline error in that probe. This is not proof that 172 websites currently respond or parse correctly.

The host remains capability-limited. No arbitrary Java reflection, file/process access or dynamic code-loading bridge is exposed. DOM/HTTP/model operations use explicit safe capabilities and execution/network budgets. Immutable bytecode is cached while each request receives fresh globals, state and budgets.

Browse lists all enabled installed sources, supports name/language filtering and pinning, and exposes real source listings with pagination where declared. Search/filter and settings defaults follow upstream typed models. Global Search has a persistent source selection, a small initial selection, bounded request concurrency, and stops obsolete queries before launching further batches. Users can explicitly select the whole catalog.

## Provenance

Repository list: https://www.shosetsu.app/help/guides/repositories.html

Full source/catalog notices are available in Settings → Open-source licenses. Community website health and source maintenance remain external to the APK.
