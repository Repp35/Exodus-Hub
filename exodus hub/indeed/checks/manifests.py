from pathlib import Path
import json
import re
ROOT = Path(__file__).resolve().parents[2]
PATTERN = r'\{\s*name\s*=\s*"(\w+)",\s*path\s*=\s*"([^"]+)"(?:,\s*hash\s*=\s*"[a-f0-9]+")?\s*\}'
def common(): return re.findall(PATTERN, (ROOT / 'core/catalog.luau').read_text())
def hub_entries(folder):
    return [(path.stem.replace("_", ""), path.relative_to(ROOT).as_posix()) for path in sorted((ROOT / 'hubs' / folder).rglob('*.luau')) if 'indeed' not in path.relative_to(ROOT).parts]
def all_entries():
    return common() + [entry for info in sorted((ROOT / 'hubs').glob('*/hub.json')) for entry in hub_entries(info.parent.name)]
def manifest(universal=True, hub_id="universal"):
    return list(dict(common() + ([] if universal else hub_entries(hub_id))).items())

def source_for(name, path):
    source = (ROOT / path).read_text()
    starts = list(re.finditer(r'local __part_(\w+)\s*=\s*\(function\(\)', source))
    if not starts: return source
    for i, match in enumerate(starts):
        if match[1] == name:
            end = starts[i+1].start() if i+1 < len(starts) else source.rfind('return {')
            part = source[match.end():end]
            import textwrap
            return textwrap.dedent(part[:part.rfind('end)()')]).strip() + '\n'
    raise ValueError(f'{path}: missing API facet {name}')
