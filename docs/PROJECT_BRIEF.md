# Hon — Project Brief

## 1. Project Overview
Hon is an Android reading app combining:
- Shosetsu-style novel discovery, sources/extensions, chapter management, and offline downloads.
- Local EPUB and PDF importing and reading.
- The visual design and interactions of Apple Books on iOS 18.
- The paragraph presentation preferred in the Apple Books typography references.
- A prompt to add a novel to the library when downloading its chapters.

The app feels like a carefully designed reading product: quiet, responsive, and focused on books.

## 2. Decision Specifications
- **Name:** Hon (本)
- **Primary platform:** Android (Flutter with Kotlin integrations where necessary)
- **Branding:** 本 / Hon calligraphic master logo
- **Main UI Reference:** Apple Books on iOS 18 (Quiet, elegant, card & shelf presentation)
- **Paragraph Reference:** iOS 18 / Apple Books typography: balanced line-height, indentation, crisp serif headers, ornate chapter dividers
- **Data Model:** Local-first; no account required
- **Backend:** No Hon backend required for the first release
- **Distribution:** Installable Android APK
- **Initial Language:** English interface; Unicode reading content

## 3. Navigation & Screen Map
Apple Books bottom-tab navigation:
1. **Home:** Continue reading, recently added books, recent activity, clean non-fabricated shelf
2. **Library:** Saved novels, imported EPUBs/PDFs, collections, grid/list view toggles, sorting/filtering
3. **Browse:** Sources, source catalogues, novel discovery
4. **Downloads:** Download queue, completed downloads, retry/pause/cancel, storage actions
5. **Search:** Combined library search and online-source search
- **Settings:** Accessible via toolbar action (no avatar / fake account icons)

## 4. Key Functional Areas
- **Library:** Add/remove novels, import books, collections, sorting, filtering, grid/list modes.
- **Reading Progress:** Continue reading, last location, reading history, explicit finished status.
- **Online Novels:** Source browsing, search, metadata, chapter list, reading, manual updates.
- **Downloads:** Single/multiple chapters, unread chapters, persistent queue, retry, pause/cancel, offline access with downloaded chapter images.
- **EPUB:** Import, metadata extraction, cover caching, pagination / vertical scrolling, typography settings.
- **PDF:** Import, page rendering, zoom, navigation, saved position.
- **Reader Tools:** Bookmarks, table of contents, typography & theme bottom sheet (`Aa` controls, 6 themes: Original, Quiet, Paper, Bold, Calm, Focus).
- **Exact Chapter-Download & Library Behaviour:** Independent library membership and downloaded content. Prompt: "Add to Library? / Add '{novel title}' to your library to find it easily and check for new chapters. / Add to Library · Not Now". Choosing "Not Now" continues the download without library membership.
