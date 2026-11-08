"""Checks to run before every push, for what this Windows PC can't compile (SwiftUI):
1. a top-level type declared twice in one module (the "invalid redeclaration" that failed a whole CI run);
2. a UI test asking for a label the app can't show (tests written for an older app stop at their first tap);
3. Core (no SwiftUI) built and tested with Swift for Windows, so only the app's own errors are left to CI.
Usage: python tools/precheck.py [UITests/X.swift ...]  (the tests about to run; all of them if none)."""
import pathlib, re, shutil, subprocess, sys

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

# 3. Core compiles and its tests pass (swift test builds it first).
if shutil.which('swift'):
    run = subprocess.run(['swift', 'test'], cwd=root / 'Core', capture_output=True, text=True, encoding='utf-8', errors='replace')
    if run.returncode:
        problems.append('Core: swift test failed\n' + '\n'.join((run.stdout + run.stderr).splitlines()[-30:]))
else:
    problems.append('Core: swift not found (Swift for Windows, winget Swift.Toolchain)')

# 4. A new version number past the newest release: SideStore offers an update only for a higher version, not a
# higher build (0.19.5 (119) over (118) showed Open, no Update, 2026-11-08).
yml = (root / 'project.yml').read_text(encoding='utf-8')
version, build = (re.search(rf'{k}: "([^"]+)"', yml)[1] for k in ('MARKETING_VERSION', 'CURRENT_PROJECT_VERSION'))
subprocess.run(['git', 'fetch', '-q', '--tags'], cwd=root, capture_output=True)
tags = subprocess.run(['git', 'tag', '--list', 'v*'], cwd=root, capture_output=True, text=True).stdout.split()
released = [(tuple(map(int, m[1].split('.'))), m[2]) for t in tags if (m := re.fullmatch(r'v([\d.]+)-(\d+)', t))]
if released and f'{version}-{build}' not in [f"{'.'.join(map(str, v))}-{b}" for v, b in released]:
    newest = max(v for v, _ in released)
    if tuple(map(int, version.split('.'))) <= newest:
        problems.append(f'project.yml: version {version} is not past the released {".".join(map(str, newest))}: SideStore will show no update')

sys.stdout.reconfigure(encoding='utf-8')
print('\n'.join(problems) or 'precheck OK')
sys.exit(1 if problems else 0)
