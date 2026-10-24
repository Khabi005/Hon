// Hon website: theme toggle, reading-theme preview, latest release links, scroll reveal.
(function () {
  'use strict';
  var root = document.documentElement;
  root.classList.add('js');

  // Light / dark toggle. With no saved choice the page follows the system.
  var toggle = document.getElementById('theme-toggle');
  function isDark() {
    if (root.dataset.theme) return root.dataset.theme === 'dark';
    return window.matchMedia('(prefers-color-scheme: dark)').matches;
  }
  if (toggle) {
    toggle.addEventListener('click', function () {
      var next = isDark() ? 'light' : 'dark';
      root.dataset.theme = next;
      try { localStorage.setItem('hon-theme', next); } catch (e) {}
    });
  }

  // Reading theme preview.
  var preview = document.getElementById('page-preview');
  var name = document.getElementById('pp-name');
  var swatches = document.querySelectorAll('.swatch');
  swatches.forEach(function (sw) {
    sw.addEventListener('click', function () {
      swatches.forEach(function (s) { s.setAttribute('aria-checked', String(s === sw)); });
      preview.style.setProperty('--pbg', sw.dataset.bg);
      preview.style.setProperty('--pfg', sw.dataset.fg);
      preview.style.setProperty('--pmuted', sw.dataset.muted);
      name.textContent = sw.dataset.themeName;
    });
  });

  // Latest release: Hon ships pre-releases, so /releases/latest would 404.
  // Pick the newest published release and link its APKs directly.
  function formatSize(bytes) { return (bytes / 1048576).toFixed(0) + ' MB'; }
  function setAsset(kind, asset) {
    var card = document.querySelector('[data-asset="' + kind + '"]');
    if (!card || !asset) return;
    card.href = asset.browser_download_url;
    card.querySelector('[data-asset-name]').textContent = asset.name;
    card.querySelector('[data-asset-size]').textContent = formatSize(asset.size);
  }
  // Cached per tab so browsing around doesn't burn the GitHub API rate limit.
  function loadReleases() {
    try {
      var cached = JSON.parse(sessionStorage.getItem('hon-releases') || 'null');
      if (cached && Date.now() - cached.at < 3600000) return Promise.resolve(cached.data);
    } catch (e) {}
    return fetch('https://api.github.com/repos/Khabi005/Hon/releases?per_page=10', {
      headers: { Accept: 'application/vnd.github+json' }
    })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (data) {
        try { sessionStorage.setItem('hon-releases', JSON.stringify({ at: Date.now(), data: data })); } catch (e) {}
        return data;
      });
  }
  loadReleases()
    .then(function (releases) {
      var rel = releases.filter(function (r) { return !r.draft; })[0];
      if (!rel) return;
      var apks = rel.assets.filter(function (a) { return /\.apk$/i.test(a.name); });
      var arm64 = apks.find(function (a) { return /arm64/i.test(a.name); });
      var universal = apks.find(function (a) { return /complete|universal/i.test(a.name); }) ||
        apks.find(function (a) { return a !== arm64 && !/armeabi|x86/i.test(a.name); });
      setAsset('arm64', arm64);
      setAsset('universal', universal);

      var date = new Date(rel.published_at).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
      document.querySelectorAll('[data-release-version]').forEach(function (el) {
        el.textContent = rel.tag_name + (rel.prerelease ? ' alpha' : '');
      });
      document.querySelectorAll('[data-release-line]').forEach(function (el) {
        el.textContent = 'Latest: ' + rel.tag_name + ', released ' + date + '.';
      });
    })
    .catch(function () { /* Static links to the Releases page stay in place. */ });

  // Gentle reveal as sections scroll into view.
  if ('IntersectionObserver' in window) {
    var targets = document.querySelectorAll('.section-head, .card, .page-preview, .gallery figure');
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
      });
    }, { rootMargin: '0px 0px -8% 0px' });
    targets.forEach(function (t) { t.classList.add('reveal'); io.observe(t); });
  }
})();
