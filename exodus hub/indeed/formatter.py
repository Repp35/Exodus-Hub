"""Format Luau with the bundled StyLua binary; --check never changes files."""
from pathlib import Path
import argparse
import hashlib
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = Path(__file__).with_name('formatting') / 'resources'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--in-place', action='store_true')
    parser.add_argument('paths', nargs='*', type=Path, default=[ROOT])
    args = parser.parse_args()
    binary = os.environ.get('STYLUA_BIN') or shutil.which('stylua')
    if not binary:
        binary = RESOURCES / 'stylua-linux-x86_64'
    files = set()
    for path in args.paths:
        if not path.exists():
            parser.error(f'Path not found: {path}')
        for candidate in path.rglob('*.luau') if path.is_dir() else [path]:
            if candidate.suffix == '.luau' and not any(part in {'.git', '__pycache__'} for part in candidate.parts):
                files.add(candidate)
    if not files:
        parser.error('No Luau files found')
    command = [str(binary), '--config-path', str(RESOURCES / 'stylua.toml'), '--verify']
    if not args.in_place:
        command.append('--check')
    command += [str(path) for path in sorted(files)]
    def fingerprint():
        return [hashlib.sha256(path.read_bytes()).digest() for path in sorted(files)]
    for _ in range(4 if args.in_place else 1):
        before = fingerprint()
        result = subprocess.run(command)
        if result.returncode or not args.in_place or fingerprint() == before:
            return result.returncode
    raise SystemExit('StyLua did not reach a stable format after four passes')


if __name__ == '__main__':
    raise SystemExit(main())
