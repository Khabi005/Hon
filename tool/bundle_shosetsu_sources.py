#!/usr/bin/env python3
"""Rebuild the offline source catalog from vendored, unmodified upstream Lua.

No network access. Update third_party/shosetsu and its provenance before running.
Module loaders retain original source text, including author/license comments.
"""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
REPOSITORIES = [
    ('universe', 'Shosetsu Universe', 'https://gitlab.com/shosetsuorg/extensions/-/raw/dev/'),
    ('noaione', 'N4O', 'https://raw.githubusercontent.com/noaione/shosetsu-extensions/repo/'),
    ('jobobby04', 'Jobobby04', 'https://jobobby04.github.io/ShosetsuExtensions/master/'),
    ('suhan', 'Suhan / Creepy Pasta', 'https://raw.githubusercontent.com/creepy-pasta101/ShosetsuExtensions/main/'),
    ('capthehacker99', 'ShosetLazy', 'https://raw.githubusercontent.com/capthehacker99/ShosetLazyExtensions/master/'),
]
REQUIRE = re.compile(r'''Require\s*\(\s*['"]([A-Za-z0-9_.\-/]+)['"]\s*\)''')
HEADER = re.compile(r'^\s*--\s*(\{[^\n]+\})')
BUILTINS = {'url', 'FilterOptions'}
OUT = ROOT / 'assets/sources/bundled'


def dependencies(source):
    header = HEADER.search(source)
    metadata = json.loads(header[1]) if header else {}
    declared = [re.split(r'[><=]', s)[0] for s in metadata.get('dep', [])]
    # Remove line comments for static Require discovery (but not the metadata).
    code = re.sub(r'--[^\n]*', '', source)
    return sorted(set(declared + REQUIRE.findall(code)))


def bundle(source, libraries, url):
    if not libraries:
        return source
    lines = [f'-- Bundled from {url}; original sources retained in third_party/shosetsu.',
        'local __modules, __loaded, __loading = {}, {}, {}',
        'local __builtin = Require',
        'local function Require(name)',
        '  if __loaded[name] ~= nil then return __loaded[name] end',
        '  if not __modules[name] then return __builtin(name) end',
        '  if __loading[name] then error("Circular library dependency: " .. name) end',
        '  __loading[name] = true',
        '  local value = __modules[name]()',
        '  if value == nil then value = true end',
        '  __loaded[name], __loading[name] = value, nil',
        '  return value', 'end']
    for name, body in libraries.items():
        lines.append(f'__modules[{json.dumps(name)}] = function()\n{body}\nend')
    lines.append(f'return (function()\n{source}\nend)()')
    return '\n'.join(lines)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    catalog = {'version': 1, 'snapshotDate': '2026-10-18', 'repositories': [], 'sources': []}
    errors = []
    for key, name, url in REPOSITORIES:
        root = ROOT / 'third_party/shosetsu' / key
        data = json.loads((root / 'index.json').read_text())
        repo_id = hashlib.sha256(url.encode()).hexdigest()
        scripts = []
        for entry in data['scripts']:
            filename = entry['fileName']
            if not filename.endswith('.lua'):
                filename += '.lua'
            file = root / 'src' / entry['lang'] / filename
            if not file.is_file():
                raise ValueError(f'Indexed source is missing: {file}')
            source = file.read_text()
            expected = entry.get('md5', '')
            actual = (hashlib.sha256 if len(expected) == 64 else hashlib.md5)(file.read_bytes()).hexdigest()
            # Upstream indexes can lag behind committed Lua. Keep the exact Lua,
            # record both hashes, and use the bundled content hash for integrity.
            if expected and expected != actual:
                errors.append({'source': f'{key}/{filename}', 'issue': 'upstream index checksum is stale', 'indexHash': expected, 'actualHash': actual})
            source_id = 'ext_' + hashlib.sha256(f"{repo_id}:{entry['lang']}:{entry['id']}".encode()).hexdigest()
            libraries, loading, missing = {}, set(), set()
            def load(lib):
                if lib in libraries or lib in loading:
                    return
                path = root / 'lib' / f'{lib}.lua'
                if not path.is_file():
                    if lib not in BUILTINS: missing.add(lib)
                    return
                loading.add(lib)
                body = path.read_text()
                for dependency in dependencies(body): load(dependency)
                libraries[lib] = body
                loading.remove(lib)
            for dependency in dependencies(source): load(dependency)
            for lib in sorted(missing): errors.append({'source': f'{key}/{filename}', 'issue': f'missing upstream module {lib}'})
            text = bundle(source, libraries, url)
            asset_name = source_id + '.lua'
            (OUT / asset_name).write_text(text)
            scripts.append(entry)
            catalog['sources'].append({
                'sourceId': source_id, 'repositoryId': repo_id, 'repositoryUrl': url,
                'scriptId': str(entry['id']), 'name': entry['name'], 'language': entry['lang'],
                'version': entry['ver'], 'asset': f'assets/sources/bundled/{asset_name}',
                'sha256': hashlib.sha256(text.encode()).hexdigest(),
            })
        catalog['repositories'].append({
            'id': repo_id, 'name': name, 'url': url, 'refreshedAt': '2026-10-18T00:00:00.000',
            'scripts': scripts,
            'libraries': {lib['name']: lib.get('ver',lib.get('version','')) for lib in data.get('libraries',[])},
        })
    (OUT / 'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
    (ROOT / 'third_party/shosetsu/SNAPSHOT_NOTES.json').write_text(json.dumps(errors,ensure_ascii=False,indent=2)+'\n')
    print(f"Bundled {len(catalog['sources'])} sources from {len(catalog['repositories'])} repositories; {len(errors)} upstream snapshot notes.")

if __name__ == '__main__': main()
