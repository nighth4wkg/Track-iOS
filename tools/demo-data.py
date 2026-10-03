# The demo training for the screenshot run: the website-checked test fixture, moved so its latest workout was
# yesterday, with no workout in progress and the theme following the simulator's appearance.
import json, sys, time

data = json.load(open('Core/Tests/TrackCoreTests/Fixtures/web-state.json'))
latest = max(s['finishedAt'] for s in data['sessions'] if s.get('finishedAt'))
delta = int(time.time() * 1000) - 26 * 3600 * 1000 - latest

def shift(value):
    if isinstance(value, dict):
        return {k: v + delta if k.endswith('At') and isinstance(v, int) else shift(v) for k, v in value.items()}
    if isinstance(value, list):
        return [shift(v) for v in value]
    return value

data = shift(data)
data['active'], data['restUntil'] = None, None
data['settings'].update(theme='system', logSets='auto')
json.dump(data, sys.stdout)
