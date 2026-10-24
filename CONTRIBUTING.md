# Contributing to Hon

Thanks for wanting to help. Hon is a small project, so a little context goes a long way.

## Before you start

- **Bugs**: search [existing issues](https://github.com/Khabi005/Hon/issues) first, then use the bug report form.
- **Bigger ideas**: open a feature request or ask on [Discord](https://discord.gg/w2XsFwFTW) before writing code, so we can agree on the approach.
- **Design**: Hon takes its look and feel from Apple Books, as a reference rather than a copy. The screen layout (five tabs: Home, Library, Browse, Search, Downloads) is settled, so polish within the existing screens rather than moving things around.

## Setup

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
```

Native Android tests run with `cd android && ./gradlew testDebugUnitTest`.

## Pull requests

1. Branch from `main` and keep each PR to one topic.
2. Run `flutter analyze` and `flutter test` before pushing. CI runs both, plus the Android unit tests.
3. Add or update tests for behaviour you change.
4. Include before and after screenshots for anything visual.
5. Describe the change in plain words in the PR template.

## Sources and extensions

Bundled sources follow the Shosetsu Lua extension format and keep their upstream headers and licenses. See [docs/SOURCE_CATALOG.md](docs/SOURCE_CATALOG.md) and [docs/LICENSING.md](docs/LICENSING.md).

## License

By contributing, you agree that your work is released under the [GPL-3.0](LICENSE), the same license as Hon.
