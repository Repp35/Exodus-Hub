"""Inventory a SrcDump ZIP/directory without executing its contents.

The tree records identity, hierarchy, attributes and tags, not geometry properties.
Report only maps/structures actually present; runtime regions obtain CFrame/Size.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import zipfile


def analyze(path: Path) -> dict:
    archive = zipfile.ZipFile(path) if path.is_file() else None
    try:
        if archive:
            names = archive.namelist()
            tree_name = next(n for n in names if n.endswith('/tree.txt'))
            prefix = tree_name[:-len('tree.txt')]
            read = lambda n: archive.read(prefix + n).decode('utf-8', errors='replace')
            scripts = [n[len(prefix):] for n in names if n.startswith(prefix + 'scripts/StarterPlayer/') and n.endswith('.lua')]
        else:
            root = path if (path / 'tree.txt').exists() else next(path.glob('*/tree.txt')).parent
            read = lambda n: (root / n).read_text(encoding='utf-8', errors='replace')
            scripts = [p.relative_to(root).as_posix() for p in (root / 'scripts/StarterPlayer').rglob('*.lua')]
        tree = read('tree.txt')
        rows = [m.groups() for m in re.finditer(r'^\[([^]]+)\] (.*?) \| discovered=', tree, re.M)]
        def children(root):
            counts = Counter()
            for _, name in rows:
                if name.startswith(root + '.'):
                    counts[name[len(root) + 1:].split('.')[0]] += 1
            return dict(sorted(counts.items()))
        loop_scripts = []
        for script in sorted(scripts):
            source = read(script)
            # Exclude the dumper's metadata, which contains game:GetDescendants.
            source = '\n'.join(line for line in source.splitlines() if not line.startswith('--'))
            features = {key: len(re.findall(pattern, source)) for key, pattern in {
                'render_callbacks': r'\.RenderStepped:Connect\(',
                'heartbeat_callbacks': r'\.Heartbeat:Connect\(',
                'roster_reads': r':GetPlayers\(',
                'subtree_reads': r':GetDescendants\(',
                'unconditional_loops': r'while true do',
            }.items()}
            if any(features.values()):
                loop_scripts.append({'path': script.split('scripts/', 1)[1], **features})
        info = dict(re.findall(r'^(\w+)=(.*)$', read('game_info.txt'), re.M))
        return {
            'tree_sha256': hashlib.sha256(tree.encode()).hexdigest(),
            'place_id': int(info['place_id']), 'place_version': int(info['place_version']),
            'reported_instances': int(info['instances']), 'instances': len(rows), 'classes': dict(sorted(Counter(c for c, _ in rows).items())),
            'workspace_roots': children('Workspace'),
            'game_roots': children('Workspace.Game'),
            'loaded_map_roots': children('Workspace.Game.Maps'),
            'crossroads_regions': children('Workspace.Game.Maps.Crossroads'),
            'crossroads_geometry': children('Workspace.Game.Maps.Crossroads.Map'),
            'lobby_regions': children('Workspace.Game.Lobby'),
            'limited_time_regions': children('Workspace.Game.LimitedTime'),
            'tbi_regions': children('Workspace.TBI'),
            'replicated_roots': children('ReplicatedStorage'),
            'map_image_catalog': list(children('ReplicatedStorage.MapImages')),
            'map_skybox_catalog': list(children('ReplicatedStorage.Map Skyboxes')),
            'client_loop_candidates': loop_scripts,
            'geometry_available': False,
            'geometry_note': 'tree.txt omits CFrame, Size, Transparency and CanCollide. Only Crossroads has loaded geometry in Game.Maps. Other catalog entries are not complete maps. Runtime indexing partitions every current/streamed map from real bounds.',
        }
    finally:
        if archive:
            archive.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dump', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    data = json.dumps(analyze(args.dump), ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(data, encoding='utf-8')
    else:
        print(data, end='')
