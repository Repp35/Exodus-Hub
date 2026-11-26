"""Format Luau and enforce the project's comment policy."""
from pathlib import Path
import argparse
import hashlib
import os
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = Path(__file__).with_name('formatting') / 'resources'

TITLE = re.compile(r'^\s*--\s*\[\[\s*[A-Za-z0-9][A-Za-z0-9 _-]*\s*\]\]\s*$')
SECTION = re.compile(r'^\s*--\s+[a-z][a-z0-9-]*\s*$')
DIRECTIVE = re.compile(r'^\s*--\s*(?:!|@).*$')


def _comment_start(line, state):
    """Return the first Lua comment outside quoted and long strings."""
    quote = None
    escaped = False
    index = 0
    while index < len(line):
        if state['long']:
            end = line.find(']]', index)
            if end < 0:
                return None
            state['long'] = False
            index = end + 2
            continue
        char = line[index]
        if quote:
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == quote:
                quote = None
            index += 1
            continue
        if line[index:index + 2] == '--':
            return index
        if line[index:index + 2] == '[[':
            state['long'] = True
            index += 2
            continue
        if char in "'\"":
            quote = char
        index += 1
    return None


def validate_comments(path):
    """Reject every source comment except one title, sections, and directives."""
    text = path.read_text()
    title_count = 0
    meaningful_seen = False
    errors = []
    state = {'long': False}
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped and not stripped.startswith('--') and not meaningful_seen:
            meaningful_seen = True
        index = _comment_start(line, state)
        if index is None:
            if stripped:
                meaningful_seen = True
            continue
        prefix = line[:index]
        if prefix.strip():
            errors.append(f'{path}:{number}: inline comments are forbidden')
            continue
        if TITLE.fullmatch(line):
            title_count += 1
            if meaningful_seen or number != next((i for i, item in enumerate(text.splitlines(), 1) if item.strip()), number):
                errors.append(f'{path}:{number}: title must be the first non-empty line')
            continue
        if SECTION.fullmatch(line) or DIRECTIVE.fullmatch(line):
            continue
        errors.append(f'{path}:{number}: unsupported descriptive comment')
    if title_count != 1:
        errors.append(f'{path}: expected exactly one title comment, found {title_count}')
    if errors:
        raise ValueError('\n'.join(errors))


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
    try:
        for path in sorted(files):
            validate_comments(path)
    except ValueError as error:
        raise SystemExit(str(error))
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
