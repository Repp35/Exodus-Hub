"""Embed the shared notification surface for loader errors before modules exist."""
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[2]
START = '-- generated-start'
END = '-- generated-end'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    path = ROOT / 'loader.luau'
    source = path.read_text()
    appearance = (ROOT / 'ui/appearance.luau').read_text().replace('-- @modules uiappearance\n', '')
    surface = (ROOT / 'ui/startup.luau').read_text().replace('-- @modules uisurface\n', '')
    expected = START + '\nlocal Appearance = (function()\n' + appearance + '\nend)()\nlocal Surface = (function()\n' + surface + '\nend)()\n' + END
    start, end = source.index(START), source.index(END) + len(END)
    updated = source[:start] + expected + source[end:]
    # Format exactly as the rest of the project, including the embedded function.
    import subprocess
    import sys
    import tempfile
    with tempfile.TemporaryDirectory() as folder:
        temp = Path(folder) / 'loader.luau'
        temp.write_text(updated)
        subprocess.run([sys.executable, str(ROOT / 'indeed/formatter.py'), '--in-place', str(temp)], check=True)
        updated = temp.read_text()
    if args.check:
        if source != updated:
            raise SystemExit('Loader notification surface is stale; run build_notification_surface.py')
    else:
        path.write_text(updated)
    print('Notification surface OK')


if __name__ == '__main__':
    main()
