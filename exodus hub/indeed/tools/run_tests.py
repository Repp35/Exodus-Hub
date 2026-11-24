"""Run universal tests and explicitly selected game-owned suites."""
from pathlib import Path
import argparse
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hub', default='all', help='all, universal, or a registered game folder')
    args = parser.parse_args()
    paths = []
    if args.hub in ('all', 'universal'):
        paths.append(ROOT / 'indeed/tests')
    if args.hub == 'all':
        paths.extend(sorted((ROOT / 'hubs').glob('*/indeed/tests')))
    elif args.hub != 'universal':
        if not (ROOT / 'hubs' / args.hub / 'hub.json').is_file():
            parser.error('Unknown game folder')
        paths.append(ROOT / 'hubs' / args.hub / 'indeed/tests')
    for path in paths:
        if not path.is_dir():
            print(f'No tests defined: {path}')
            continue
        print(f'Testing {path.relative_to(ROOT)}', flush=True)
        result = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(path), '-p', 'test_*.py'])
        if result.returncode:
            return result.returncode
    return 0

if __name__ == '__main__': raise SystemExit(main())
