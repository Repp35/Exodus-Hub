"""Discover hub folders and generate the loader's immutable game catalog."""
from pathlib import Path
import argparse
import json
import re
import hashlib
import math

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_AUTHOR = 'deltapolinha_2915'

def shared(root=ROOT):
    entries, seen = [], set()
    for folder in ('core', 'ui', 'universal'):
        for path in sorted((root / folder).rglob('*.luau')):
            if path.name == 'catalog.luau' or path.is_relative_to(root / 'ui/games'): continue
            source = path.read_text()
            marker = re.search(r'^-- @modules ([\w, ]+)$', source, re.M)
            if not marker: raise ValueError(f'{path}: @modules declaration required')
            for name in marker[1].replace(' ', '').split(','):
                if not name or name in seen: raise ValueError(f'{path}: duplicate module {name}')
                seen.add(name)
                entries.append({'name': name, 'path': path.relative_to(root).as_posix(), 'hash': hashlib.sha256(path.read_bytes()).hexdigest()})
    return entries

def discover(root=ROOT):
    profiles, ids, places, universes = [], set(), set(), set()
    reserved = {entry["name"] for entry in shared(root)}
    for info in sorted((root / 'hubs').glob('*/hub.json')):
        profile = json.loads(info.read_text())
        ident = profile.get('id', info.parent.name)
        if ident != info.parent.name or not re.fullmatch(r'[a-z0-9-]+', ident) or ident == 'universal' or ident in ids:
            raise ValueError(f'{info}: invalid or duplicate ID')
        ids.add(ident)
        if not isinstance(profile.get('title'), str) or not profile['title'].strip():
            raise ValueError(f'{info}: title required')
        for field in ['author', 'notification']:
            if field in profile and (not isinstance(profile[field], str) or not profile[field].strip()):
                raise ValueError(f'{info}: {field} must be a nonempty string')
        for field, used in [('placeIds', places), ('universeIds', universes)]:
            values = profile.get(field, [])
            if not isinstance(values, list) or any(type(value) is not int or value <= 0 or value in used for value in values) or len(set(values)) != len(values):
                raise ValueError(f'{info}: invalid or duplicate {field}')
            used.update(values)
        if not profile.get('placeIds') and not profile.get('universeIds'):
            raise ValueError(f'{info}: at least one game ID required')
        defaults = profile.get('defaults', {})
        if not isinstance(defaults, dict) or any(not re.fullmatch(r'[A-Za-z_]\w*', key) or type(value) not in (int, float, bool, str) or isinstance(value, float) and not math.isfinite(value) for key, value in defaults.items()):
            raise ValueError(f'{info}: invalid defaults')
        modules, seen = [], set()
        for path in sorted([*info.parent.rglob('*.luau'), *(root / 'ui/games' / ident).rglob('*.luau')]):
            if "indeed" in path.relative_to(root).parts: continue
            name = path.stem.replace("_", "")
            if not re.fullmatch(r'\w+', name) or name in seen or name in reserved:
                raise ValueError(f'{path}: duplicate, reserved or invalid module name')
            if '__contract' not in path.read_text():
                raise ValueError(f'{path}: module contract required')
            seen.add(name)
            modules.append({'name': name, 'path': path.relative_to(root).as_posix(), 'hash': hashlib.sha256(path.read_bytes()).hexdigest()})
        profiles.append({**profile, 'id': ident, 'author': profile.get('author', DEFAULT_AUTHOR),
                         'notification': profile.get('notification', f"Exodus Hub · {profile['title']} carregado."), 'modules': modules})
    return profiles

def literal(value):
    if isinstance(value, str): return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list): return '{ ' + ', '.join(literal(item) for item in value) + ' }'
    if isinstance(value, dict): return '{ ' + ', '.join(f'{key} = {literal(item)}' for key, item in value.items()) + ' }'
    if type(value) is bool: return "true" if value else "false"
    if type(value) in (int, float): return str(value)
    raise ValueError(f'Unsupported catalog value: {value!r}')

def render(profiles):
    return '-- [[ catalog ]]\n--!strict\n--!optimize 2\n\n-- generated\nreturn {\n' + ''.join('  ' + literal(profile) + ',\n' for profile in profiles) + '}\n'

def tokens(text):
    return [part for part in re.findall(r'--[^\n]*|"(?:\\.|[^"\\])*"|[^\s]', text) if (not part.startswith('--') or part.startswith('--!')) and part != ',']

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    outputs = {ROOT / 'hubs/catalog.luau': render(discover()), ROOT / 'core/catalog.luau': render(shared())}
    for path, expected in outputs.items():
        if args.check:
            if not path.exists() or tokens(path.read_text()) != tokens(expected):
                raise SystemExit(f'{path.name} is stale. Run build_hub_catalog.py.')
        else:
            path.write_text(expected)
    # Package runtime sources together: startup fetches one immutable archive,
    # not a separate HTTP request for every module. Catalog text is canonical.
    sources = {}
    for folder in ('core', 'ui', 'universal', 'hubs'):
        for source in sorted((ROOT / folder).rglob('*.luau')):
            if 'indeed' in source.relative_to(ROOT).parts: continue
            sources[source.relative_to(ROOT).as_posix()] = outputs[source] if source in outputs else source.read_text()
    archive = ROOT / 'dist/runtime.json'
    expected = json.dumps({'version': 1, 'sources': sources}, ensure_ascii=False, separators=(',', ':')) + '\n'
    if args.check:
        if not archive.exists() or archive.read_text() != expected:
            raise SystemExit('Runtime package is stale. Run build_hub_catalog.py.')
    else:
        archive.parent.mkdir(parents=True, exist_ok=True)
        archive.write_text(expected)
    print('Hub catalog and runtime package OK')

if __name__ == '__main__': main()
