"""Update or validate the offline PNG payloads used by the Roblox UI icon adapter."""
from __future__ import annotations

import argparse
import base64
import hashlib
import re
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / 'ui/icons.luau'
NAMES = ('settings', 'chevron', 'minimize', 'assists')


def validate_png(image: bytes, name: str) -> None:
    if not image.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError(f'{name}: expected a PNG image')
    offset = 8
    ended = False
    while offset + 12 <= len(image):
        length = struct.unpack_from('>I', image, offset)[0]
        end = offset + 12 + length
        if end > len(image):
            raise ValueError(f'{name}: truncated PNG chunk')
        chunk = image[offset + 4:end - 4]
        checksum = struct.unpack_from('>I', image, end - 4)[0]
        if zlib.crc32(chunk) & 0xffffffff != checksum:
            raise ValueError(f'{name}: corrupt PNG chunk')
        offset = end
        if chunk[:4] == b'IEND':
            ended = True
            break
    if not ended or offset != len(image):
        raise ValueError(f'{name}: incomplete PNG image')


def generated(source: str) -> str:
    fingerprint = hashlib.sha256()
    for name in NAMES:
        image = (ROOT / 'ui/assets' / f'{name}.png').read_bytes()
        validate_png(image, name)
        fingerprint.update(name.encode() + b'\0' + image)
        encoded = base64.b64encode(image).decode()
        pattern = rf'(\b{name}\s*=\s*\{{\s*png\s*=\s*")[^"]*(")'
        source, count = re.subn(pattern, lambda match: match[1] + encoded + match[2], source)
        if count != 1:
            raise ValueError(f'{name}: missing or ambiguous icon payload')
    source, count = re.subn(r'\bVERSION\s*=\s*"[^"]*"',
                            f'VERSION = "{fingerprint.hexdigest()[:12]}"', source)
    if count != 1:
        raise ValueError('Missing or ambiguous icon version')
    return source


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    current = MODULE.read_text()
    expected = generated(current)
    if args.check:
        if expected != current:
            raise SystemExit('UI PNG payloads are stale; run indeed/tools/build_ui_icons.py')
        print('UI PNG payloads match their source assets.')
    elif current != expected:
        MODULE.write_text(expected)
        print('Updated embedded UI PNGs and cache version.')
