# Summarises a Time Profiler export (xctrace export … --xpath …time-profile) for the app's main thread, phase by phase
# (busy stretches split by quiet seconds): what kind of work it was, and where inside it the time went.
import collections, sys, xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
app = sys.argv[2] if len(sys.argv) > 2 else "Track"
ids = {e.get("id"): e for e in root.iter() if e.get("id")}
def get(e):
    return ids[e.get("ref")] if e is not None and e.get("ref") else e

samples = []  # (seconds, ms, frames leaf first)
for row in root.iter("row"):
    thread = get(row.find("thread"))
    fmt = (thread.get("fmt") or "") if thread is not None else ""
    if "Main Thread" not in fmt or app not in fmt:
        continue
    backtrace = get(row.find("backtrace"))
    frames = [(get(f).get("name") or get(f).get("addr") or "?") for f in backtrace.findall("frame")] if backtrace is not None else []
    samples.append((int(get(row.find("sample-time")).text) / 1e9, int(get(row.find("weight")).text) / 1e6, frames))
samples.sort(key=lambda s: s[0])

# Phases: busy stretches with at least 2 s of near-quiet between them.
per_second = collections.Counter(int(t) for t, ms, _ in samples for _ in [0])
busy = collections.Counter()
for t, ms, _ in samples:
    busy[int(t)] += ms
phases, current = [], []
for second in range(int(samples[-1][0]) + 1 if samples else 0):
    if busy[second] > 50:
        if current and second - current[-1] > 2:
            phases.append(current); current = []
        current.append(second)
if current:
    phases.append(current)

KINDS = [("focus switch (becomeFirstResponder)", "becomeFirstResponder"), ("keyboard reload", "reloadInputViews"),
         ("SwiftUI update", "ViewGraph"), ("SwiftUI update", "AG::"), ("Core Animation commit", "CA::Transaction"),
         ("text layout", "CoreText"), ("other", "")]
OURS = ("body.getter", "WorkoutView", "ExerciseCard", "SetRow", "CardFocus", "WorkoutBottomBar", "RestCapsule", "Glass",
        "FrameLog", "ReorderBox", "RecordBests", "TrainingSet", "AppModel", "Training")

for n, seconds in enumerate(phases, 1):
    lo, hi = seconds[0], seconds[-1] + 1
    part = [s for s in samples if lo <= s[0] < hi]
    total = sum(ms for _, ms, _ in part)
    print(f"\n===== phase {n}: {lo}s–{hi}s, main thread busy {total:.0f} ms")
    kinds = collections.Counter()
    for _, ms, frames in part:
        stack = " | ".join(frames)
        kinds[next(kind for kind, key in KINDS if key in stack)] += ms
    for kind, ms in kinds.most_common():
        print(f"  {ms:7.0f} ms  {kind}")
    inclusive, ours, under_focus = collections.Counter(), collections.Counter(), collections.Counter()
    for _, ms, frames in part:
        for name in set(frames):
            inclusive[name] += ms
            if any(key in name for key in OURS):
                ours[name] += ms
        i = next((i for i, f in enumerate(frames) if "becomeFirstResponder" in f), None)
        if i is not None:
            for name in set(frames[:i]):
                under_focus[name] += ms
    print("  -- our code (inclusive) --")
    for name, ms in ours.most_common(25):
        print(f"  {ms:7.0f} ms  {name[:140]}")
    print("  -- inside becomeFirstResponder --")
    for name, ms in under_focus.most_common(25):
        print(f"  {ms:7.0f} ms  {name[:140]}")
