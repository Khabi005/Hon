# Hon website

The static site behind https://khabi005.github.io/Hon/. Plain HTML, CSS and a little JavaScript, no build step.

- `index.html` holds all page content.
- `style.css` follows the app palette in `lib/app/theme/hon_colors.dart` and switches with the system light/dark setting.
- `main.js` handles the theme toggle, the reading theme preview, and fills the download cards from the newest GitHub release.
- `assets/screens/` are WebP copies of `docs/screenshots/`. Re-export them when the app screenshots change.

Preview locally with `python3 -m http.server -d website` and open http://localhost:8000.

Every push to `main` that touches `website/` deploys through `.github/workflows/pages.yml`.
