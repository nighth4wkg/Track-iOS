"""Checks to run before every push, for what this Windows PC can't compile (SwiftUI):
1. a top-level type declared twice in one module (the "invalid redeclaration" that failed a whole CI run);
2. a UI test asking for a label the app can't show (tests written for an older app stop at their first tap).
Usage: python tools/precheck.py [UITests/X.swift ...]  (the tests about to run; all of them if none)."""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
problems = []

# 1. One name, one top-level type, per module (nested ones, like CodingKeys, may repeat).
for module in ['App', 'Widgets', 'Core/Sources', 'UITests']:
    seen = {}
    for f in sorted((root / module).rglob('*.swift')):
        for n, line in enumerate(f.read_text(encoding='utf-8').splitlines(), 1):
            m = re.match(r'(?:(?:public|private|fileprivate|internal|final)\s+)*(?:struct|class|enum|protocol|actor|typealias)\s+(\w+)', line)
            if not m:
                continue
            if m[1] in seen:
                problems.append(f'{module}: {m[1]} declared twice: {seen[m[1]]} and {f.relative_to(root)}:{n}')
            else:
                seen[m[1]] = f'{f.relative_to(root)}:{n}'

# 2. Every exact label a UI test asks for is one the app can show: a string in its source (any \(...) in it stands for
# anything), or a name from the demo data or the exercise list.
patterns = []
for f in (root / 'App').rglob('*.swift'):
    for lit in re.findall(r'"((?:[^"\\\n]|\\.)*)"', f.read_text(encoding='utf-8')):
        parts = re.split(r'\\\((?:[^()]|\([^()]*\))*\)', lit)
        if any(parts):
            patterns.append(re.compile('.+'.join(re.escape(p) for p in parts)))
data = '\n'.join(f.read_text(encoding='utf-8') for f in [*(root / 'tools').glob('demo-data.py'), *(root / 'Core').rglob('*.json')])
tests = [root / a for a in sys.argv[1:]] or sorted((root / 'UITests').glob('*.swift'))
for f in tests:
    for n, line in enumerate(f.read_text(encoding='utf-8').splitlines(), 1):
        for label in re.findall(r'\.(?:buttons|staticTexts|textFields)\["([^"\\]+)"\]', line):
            if f'"{label}"' not in data and not any(p.fullmatch(label) for p in patterns):
                problems.append(f'{f.relative_to(root)}:{n}: "{label}" is not a label the app has')

sys.stdout.reconfigure(encoding='utf-8')
print('\n'.join(problems) or 'precheck OK')
sys.exit(1 if problems else 0)
