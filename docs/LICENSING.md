# Hon Licensing & Intellectual Property Documentation

## 1. Overview & Architecture Boundaries

**Hon** is an Android reading application built using Flutter for the user interface, custom native Android Kotlin services, and embedded runtimes for publication formats and novel sources.

Because Hon integrates components licensed under copyleft licenses (notably GPL-3.0-or-later) alongside permissive open-source frameworks, this document clarifies the architectural boundaries, dependency licenses, and asset attributions.

---

## 2. Bundled Shosetsu Lua Extensions & Standard Library

### 2.1 Upstream Provenance
- **Upstream Project:** [Shosetsu](https://gitlab.com/shosetsuorg) / [kotlin-lib](https://gitlab.com/shosetsuorg/kotlin-lib)
- **License:** GNU General Public License v3.0 or later (GPL-3.0-or-later)
- **Local Copy:** `assets/legal/shosetsu-LICENSE.txt` and `assets/legal/shosetsu-NOTICE.txt`
- **Catalog Notices:** `assets/legal/source-catalog-NOTICES.txt`
- **Bundled Files:**
  - Standard Lua library helpers (`assets/sources/`):
    - `shosetsu_init.lua`
    - `shosetsu_network.lua`
    - `shosetsu_dom.lua`
    - `shosetsu_bridge.lua`
  - Bundled source extensions (`assets/sources/bundled/*.lua`)

### 2.2 Boundary & Compliance
- Bundled Lua extensions are interpreted scripts executed within Hon's sandboxed `ShosetsuKotlinEngine` via LuaJ.
- Upstream copyright notices, source headers, and metadata headers are strictly preserved verbatim across all bundled `.lua` source files.
- Full source code for all bundled Lua extensions is distributed inside the application bundle (`assets/sources/bundled/`) in accordance with GPL-3.0 section 6.

---

## 3. Bundled Typography & Fonts

All bundled typefaces are distributed under the **SIL Open Font License, Version 1.1 (OFL-1.1)**. No fonts are fetched dynamically at runtime; all fonts are bundled locally as static assets.

| Font Family | Designer / Foundary | License File | Asset Paths |
|---|---|---|---|
| **Newsreader** | Production Type | `assets/legal/newsreader-OFL.txt` | `assets/fonts/newsreader-Regular.ttf`, `assets/fonts/newsreader-Italic.ttf` |
| **Literata** | TypeTogether | `assets/legal/literata-OFL.txt` | `assets/fonts/literata-Regular.ttf`, `assets/fonts/literata-Italic.ttf` |
| **Lora** | Cyreal | `assets/legal/lora-OFL.txt` | `assets/fonts/lora-Regular.ttf`, `assets/fonts/lora-Italic.ttf` |
| **Libre Baskerville** | Impallari Type | `assets/legal/librebaskerville-OFL.txt` | `assets/fonts/librebaskerville-Regular.ttf`, `assets/fonts/librebaskerville-Italic.ttf` |

---

## 4. Native Android & Third-Party Dependencies

| Library | Function | Upstream License |
|---|---|---|
| **Readium Kotlin Toolkit** (`3.1.1`) | EPUB publication parsing, navigator, streamer | BSD 3-Clause |
| **LuaJ** (`3.0.1`) | Sandboxed JVM Lua 5.2 interpreter | MIT License |
| **Jsoup** (`1.18.1`) | HTML DOM parsing for Lua environment | MIT License |
| **OkHttp** (`4.12.0`) | HTTP client for source updates and downloads | Apache License 2.0 |
| **Google Guava** (`33.3.1-android`) | InternetDomainName network policy allowlisting | Apache License 2.0 |
| **AndroidX WorkManager** (`2.9.1`) | Durable background chapter downloads | Apache License 2.0 |
| **AndroidX AppCompat & Fragment** | Android UI lifecycle and platform fragments | Apache License 2.0 |
| **Desugar JDK Libs** (`2.1.4`) | Java 8+ API desugaring on Android | GPLv2 with Classpath Exception |
| **pdfx** (`2.6.0`) | Native Android PDF renderer integration | BSD 3-Clause |
| **Drift & sqlite3** | Local SQLite persistence, migrations, and WAL | MIT License |
| **Flutter SDK & Cupertino Icons** | Cross-platform framework and icons | BSD 3-Clause & MIT |

---

## 5. Assets, Branding, and Fixtures

- **Branding Assets** (`assets/branding/`): Hon app icons, splash screens, and vector artwork are proprietary to the Hon project.
- **Fixtures** (`assets/fixtures/`): Test EPUB and novel fixtures are derived from public domain works (Project Gutenberg) and used strictly for parsing verification.
