"""Check fixed family capabilities, API compatibility and dependency access.

No Roblox execution, network access or test harness is required. UI controllers
receive the UI's restricted dependency views; their accesses are checked against
that consumer too. Computed members and arbitrary runtime table transfers still
need runtime enforcement by permissions.luau.
"""
from __future__ import annotations
import re
import json
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOKEN = re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', re.S)


def clean(source: str, strings: bool = False) -> str:
    def replace(match):
        value = match.group()
        if value.startswith('--') or strings:
            return ''.join('\n' if c == '\n' else ' ' for c in value)
        return value
    return TOKEN.sub(replace, source)


def table(source: str, name: str) -> str:
    match = re.search(r'\b' + re.escape(name) + r'\s*=\s*\{', source)
    if not match:
        return ''
    masked = clean(source, strings=True)
    start, depth = match.end(), 1
    for index in range(start, len(source)):
        if masked[index] == '{':
            depth += 1
        elif masked[index] == '}':
            depth -= 1
            if depth == 0:
                return source[start:index]
    raise ValueError(f'Unclosed table: {name}')


def names(source: str) -> set[str]:
    return set(re.findall(r'"([\w]+)"', source))


def lists(source: str) -> dict[str, set[str]]:
    return {alias: names(body) for alias, body in re.findall(r'(\w+)\s*=\s*\{([^{}]*)\}', source)}


SPEC = json.loads(re.search(r'local POLICY_JSON\s*=\s*\[=\[(.*?)\]=\]', (ROOT / 'modules/logic/aux/permissions.luau').read_text(), re.S)[1])
MODULES = {}

def family(name, path):
    for rule in SPEC['rules']:
        if (rule.get('prefix') and path.startswith(rule['prefix'])) or name in rule.get('names', []):
            return rule['family']
    raise ValueError(f'Module has no family: {name}')

def capability(provider, member, data=False):
    if data:
        if member in MODULES[provider].get('commandData', set()):
            return SPEC['domains'][MODULES[provider]['family']]
        return 'internal.read'
    if member in SPEC['lifecycleMethods']:
        return 'lifecycle.write'
    definition = SPEC['providers'].get(provider, {})
    if member in definition.get('methods', {}):
        return definition['methods'][member]
    if any(member.startswith(prefix) for prefix in SPEC['readPrefixes']):
        return 'internal.read'
    if any(member.startswith(prefix) for prefix in SPEC['subscribePrefixes']):
        return 'lifetime.manage'
    return definition.get('default', SPEC['domains'][MODULES[provider]['family']])

def permitted(consumer, provider, member, data=False):
    grants = set(SPEC['families'][consumer['family']]) | set(SPEC['base'])
    permission = capability(provider, member, data)
    own = provider == 'utils' and member == 'setConfig' and 'config.own' in grants
    return ('*' in grants or permission in grants or own), ('config.own' if own and permission not in grants else permission)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', action='store_true', help='List every module and its fixed family capabilities')
    arguments = parser.parse_args()
    entries = re.findall(r'\{\s*name\s*=\s*"(\w+)",\s*path\s*=\s*"([^"]+)"\s*\}', (ROOT / 'loader.luau').read_text())
    modules, errors = {}, []
    manifest_paths = {path for _, path in entries}
    actual_paths = {str(path.relative_to(ROOT)) for path in (ROOT / 'modules').rglob('*.luau')}
    for path in sorted(actual_paths - manifest_paths):
        errors.append(f'{path}: module outside the manifest has no reviewed family')
    global MODULES
    MODULES = modules
    for name, path in entries:
        source = clean((ROOT / path).read_text())
        contract = table(source, '__contract')
        if not contract:
            errors.append(f'{path}: missing literal __contract')
            continue
        modules[name] = dict(family=family(name, path), path=path, source=source, code=clean(source, strings=True),
                             exports=names(table(contract, 'provides')),
                             data=names(table(contract, 'data')),
                             requires=dict(re.findall(r'(\w+)\s*=\s*"(\w+)"', table(contract, 'requires'))),
                             methods=lists(table(contract, 'requiresMethods')),
                             fields=lists(table(contract, 'requiresData')))
    for module in modules.values():
        module['commandData'] = set()
        for field in module['data']:
            assignment = re.search(r'\b\w+\.' + re.escape(field) + r'\s*=\s*(\w+)\b', module['code'])
            if assignment:
                variable = re.escape(assignment[1])
                if re.search(r'\bfunction\s+' + variable + r'[.:]|\b' + variable + r'(?:\[[^\n]*?\]|\.\w+)\s*=\s*function', module['code']):
                    module['commandData'].add(field)
    for owner, module in modules.items():
        returned = re.search(r'\breturn\s+(\w+)\s*$', module['code'])
        if returned:
            prefix = re.escape(returned[1])
            public_functions = set(re.findall(r'\bfunction\s+' + prefix + r'\.(\w+)\s*\(', module['code']))
            public_functions.update(re.findall(r'\b' + prefix + r'\.(\w+)\s*=\s*function\b', module['code']))
            for member in public_functions - module['exports']:
                errors.append(f'{owner}: public function {member} missing from provides')
            for member in module['exports'] | module['data']:
                if not re.search(r'\b' + prefix + r'\.' + re.escape(member) + r'\s*(?:=|\()', module['code']):
                    errors.append(f'{owner}: declared export {member} has no static definition')
        for alias, provider in module['requires'].items():
            if provider not in modules:
                errors.append(f'{owner}: missing dependency {provider}')
                continue
            for kind, exported in [('methods', 'exports'), ('fields', 'data')]:
                for member in module[kind].get(alias, set()):
                    if member not in modules[provider][exported]:
                        errors.append(f'{owner}: {alias}.{member} is not exported by {provider}')
                    else:
                        ok, permission = permitted(module, provider, member, kind == 'fields')
                        if not ok:
                            errors.append(f'{owner} [{module["family"]}]: import {alias}.{member} requires forbidden capability {permission}')
        for kind in ['methods', 'fields']:
            for alias in module[kind].keys() - module['requires'].keys():
                errors.append(f'{owner}: {kind} declared for unknown dependency {alias}')

    # Context.create(deps) retains the UI dependency views in context.deps.
    forwarded = {name for name, m in modules.items() if '/front/controllers/' in m['path']}
    accesses = 0
    for name, module in modules.items():
        owner = 'ui' if name in forwarded else name
        consumer = modules[owner]
        code = module['code']
        if consumer['family'] not in {'infrastructure', 'presentation'} and re.search(r'\b(?:_G\.)?Exodus\.(?:Context|Modules|UI)\b|\b_G\.ExodusUI\w*', code):
            errors.append(f"{module['path']}: direct access to the hub registry/UI bypasses family APIs")
        aliases: dict[str, str] = {}
        dep_pattern = r'(?:context\.)?deps\.(\w+)'
        for match in re.finditer(dep_pattern + r'\.(\w+)', code):
            alias, member = match.groups()
            if alias in consumer['requires']:
                accesses += 1
                check(errors, module, consumer, owner, alias, member, match.start())
        # Follow simple single/multiple assignments, including boundUtils aliases.
        assignments = list(re.finditer(r'\b(?:local\s+)?([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*=\s*([^\n;]+)', code))
        for _ in range(8):
            changed = False
            for match in assignments:
                left = [x.strip() for x in match[1].split(',')]
                right = [x.strip() for x in match[2].split(',')]
                for variable, expression in zip(left, right):
                    dep = re.fullmatch(dep_pattern, expression)
                    alias = dep[1] if dep else aliases.get(expression)
                    if alias in consumer['requires'] and aliases.get(variable) != alias:
                        aliases[variable] = alias
                        changed = True
            if not changed:
                break
        for variable, alias in aliases.items():
            for match in re.finditer(r'\b' + re.escape(variable) + r'\.(\w+)', code):
                accesses += 1
                check(errors, module, consumer, owner, alias, match[1], match.start())
    # Architectural invariants: combat remains one profile, without UI/config ownership.
    combat = set(SPEC['families']['combat']) | set(SPEC['base'])
    if combat & {'*', 'ui.write', 'config.write', 'manual.input.write', 'hub.control', 'infrastructure.write', 'lifecycle.write', 'game.write', 'game.inventory', 'ui.write', 'world.write', 'render.write', 'tooling.execute', 'input.stop'}:
        errors.append('combat family must not own UI, configuration, manual input, or infrastructure')
    if len({modules[name]['family'] for name in ['autoparry', 'autospam', 'spam', 'dynamicparry']}) != 1:
        errors.append('AP, AutoSpam, Spam and DynamicParry must share one family')
    if arguments.report:
        for name, module in modules.items():
            grants = sorted(set(SPEC['base']) | set(SPEC['families'][module['family']]))
            print(f"{name}: {module['family']} -> {', '.join(grants)}")
    if errors:
        print('Permission verification failed:', file=sys.stderr)
        for error in sorted(set(errors)):
            print('  ' + error, file=sys.stderr)
        return 1
    print(f'Permissions OK: {len(modules)} modules; {accesses} static accesses; {len(SPEC["families"])} fixed families (including UI forwarding).')
    return 0


def check(errors, module, consumer, owner, alias, member, offset):
    provider = consumer['requires'][alias]
    target = MODULES[provider]
    line = module['source'].count('\n', 0, offset) + 1
    if member not in target['exports'] | target['data']:
        errors.append(f"{module['path']}:{line}: missing export {provider}.{member}")
        return
    ok, permission = permitted(consumer, provider, member, member in target['data'])
    if not ok:
        errors.append(f"{module['path']}:{line}: {owner} [{consumer['family']}] cannot use {provider}.{member}: {permission}")
    elif permission == 'config.own':
        call = re.match(r'\w+\.setConfig\s*\(\s*\{([^}]*)\}', module['code'][offset:])
        if call:
            prefix = SPEC['ownConfigPrefixes'][consumer['family']]
            for key in re.findall(r'\b(\w+)\s*=(?!=)', call[1]):
                if not key.startswith(prefix):
                    errors.append(f"{module['path']}:{line}: {consumer['family']} cannot write config key {key}")


if __name__ == '__main__':
    raise SystemExit(main())
