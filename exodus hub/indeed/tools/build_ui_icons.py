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


def monochrome_png(image: bytes) -> bytes:
    """Normalize the RGB mask; ImageColor3 then applies the exact theme tint."""
    width, height, depth, color, _, _, interlace = struct.unpack_from('>IIBBBBB', image, 16)
    if (depth, color, interlace) != (8, 6, 0):
        raise ValueError('Icons must use non-interlaced 8-bit RGBA PNG')
    compressed, offset = bytearray(), 8
    while offset < len(image):
        length = struct.unpack_from('>I', image, offset)[0]
        if image[offset + 4:offset + 8] == b'IDAT': compressed.extend(image[offset + 8:offset + 8 + length])
        offset += length + 12
    raw = zlib.decompress(compressed)
    stride, previous, rows = width * 4, bytearray(width * 4), bytearray()
    def paeth(a, b, c):
        p = a + b - c
        distances = (abs(p - a), abs(p - b), abs(p - c))
        return (a, b, c)[distances.index(min(distances))]
    for y in range(height):
        pos = y * (stride + 1)
        mode, row = raw[pos], bytearray(raw[pos + 1:pos + 1 + stride])
        if mode > 4: raise ValueError('Invalid PNG filter')
        for x in range(stride):
            left, up, diagonal = row[x - 4] if x >= 4 else 0, previous[x], previous[x - 4] if x >= 4 else 0
            prediction = (0, left, up, (left + up) // 2, paeth(left, up, diagonal))[mode]
            row[x] = (row[x] + prediction) & 255
        previous = row
        rows.append(0)
        for x in range(0, stride, 4): rows.extend((255, 255, 255, row[x + 3]))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    header = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')


def generated(source: str) -> str:
    fingerprint = hashlib.sha256()
    for name in NAMES:
        image = (ROOT / 'ui/assets' / f'{name}.png').read_bytes()
        validate_png(image, name)
        image = monochrome_png(image)
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
