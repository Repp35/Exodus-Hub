"""Verify internal API permissions using the same engine as the loader."""
from pathlib import Path
import argparse
import importlib.util
import json
import os
import shutil
ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hub', default='universal')
    args = parser.parse_args()
    info = ROOT / 'hubs' / args.hub / 'hub.json'
    profile = json.loads(info.read_text()) if info.exists() else {}
    binary = os.environ.get('LUAU_BIN') or shutil.which('luau')
    if not binary:
        raise SystemExit('Luau required to verify the active internal permission policy')
    spec = importlib.util.spec_from_file_location('runtime_api', ROOT / 'indeed/checks/runtime_api.py')
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    helper.smoke(binary, hub_id=args.hub)
    print('Permission policy and API dependencies OK')
    return 0

if __name__ == '__main__': raise SystemExit(main())
