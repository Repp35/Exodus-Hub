"""Check literal module contracts and statically visible dependency access.

No Roblox execution, network access or test harness is required. UI controllers
receive the UI's restricted dependency views; their accesses are checked against
that consumer too. Computed members and arbitrary runtime table transfers still
need runtime enforcement by permissions.luau.
"""
from __future__ import annotations
import re
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


def main() -> int:
    entries = re.findall(r'\{\s*name\s*=\s*"(\w+)",\s*path\s*=\s*"([^"]+)"\s*\}', (ROOT / 'loader.luau').read_text())
    modules, errors = {}, []
    for name, path in entries:
        source = clean((ROOT / path).read_text())
        contract = table(source, '__contract')
        if not contract:
            errors.append(f'{path}: missing literal __contract')
            continue
        modules[name] = dict(path=path, source=source, code=clean(source, strings=True),
                             exports=names(table(contract, 'provides')),
                             data=names(table(contract, 'data')),
                             requires=dict(re.findall(r'(\w+)\s*=\s*"(\w+)"', table(contract, 'requires'))),
                             methods=lists(table(contract, 'requiresMethods')),
                             fields=lists(table(contract, 'requiresData')))
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
    if errors:
        print('Permission verification failed:', file=sys.stderr)
        for error in sorted(set(errors)):
            print('  ' + error, file=sys.stderr)
        return 1
    print(f'Permissions OK: {len(modules)} modules; {accesses} static accesses checked (including UI forwarding).')
    return 0


def check(errors, module, consumer, owner, alias, member, offset):
    allowed = consumer['methods'].get(alias, set()) | consumer['fields'].get(alias, set())
    if member not in allowed:
        line = module['source'].count('\n', 0, offset) + 1
        errors.append(f"{module['path']}:{line}: {owner} -> {alias}.{member} missing in requiresMethods/requiresData")


if __name__ == '__main__':
    raise SystemExit(main())
