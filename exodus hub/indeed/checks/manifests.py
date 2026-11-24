from pathlib import Path
import json
import re
ROOT = Path(__file__).resolve().parents[2]
PATTERN = r'\{\s*name\s*=\s*"(\w+)",\s*path\s*=\s*"([^"]+)"\s*\}'
def common(): return re.findall(PATTERN, (ROOT / 'loader.luau').read_text())
def hub_entries(folder):
    return [(path.stem, path.relative_to(ROOT).as_posix()) for path in sorted((ROOT / 'hubs' / folder).rglob('*.luau'))]
def all_entries():
    return common() + [entry for info in sorted((ROOT / 'hubs').glob('*/hub.json')) for entry in hub_entries(info.parent.name)]
def manifest(universal=False, hub_id="phantom-ball"):
    return list(dict(common() + ([] if universal else hub_entries(hub_id))).items())
