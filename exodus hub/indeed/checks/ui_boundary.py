"""Enforce ownership of UI construction in runtime source files."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
GUI_CLASSES = {
    'ScreenGui', 'BillboardGui', 'SurfaceGui', 'Frame', 'CanvasGroup',
    'ScrollingFrame', 'TextLabel', 'TextButton', 'TextBox', 'ImageLabel',
    'ImageButton', 'ViewportFrame', 'VideoFrame',
}


def violations(root=ROOT):
    errors = []
    for path in sorted(root.rglob('*.luau')):
        relative = path.relative_to(root)
        if relative.parts[0] == 'ui' or 'indeed' in relative.parts:
            continue
        source = path.read_text()
        if relative.as_posix() == 'loader.luau':
            source = re.sub(r'-- generated-start\n.*?-- generated-end', '', source, flags=re.S)
        source = re.sub(r'--\[\[.*?\]\]|--[^\n]*', '', source, flags=re.S)
        for match in re.finditer(r'Instance\s*\.\s*new\s*\(\s*["\']([^"\']+)["\']', source):
            kind = match[1]
            if kind in GUI_CLASSES or kind.startswith('UI'):
                errors.append(f'{relative}: {kind} construction belongs to ui/')
        if re.search(r'\bDrawing\s*\.\s*new\s*\(', source):
            errors.append(f'{relative}: Drawing construction belongs to ui/')
    return errors
