# Summarises a Time Profiler export (xctrace export … --xpath …time-profile) for the app's main thread: where the time
# went (functions with the most time inside them, and at the top of the stack), and busy milliseconds per second.
import collections, sys, xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
app = sys.argv[2] if len(sys.argv) > 2 else "Track"
ids = {e.get("id"): e for e in root.iter() if e.get("id")}
def get(e):
    return ids[e.get("ref")] if e is not None and e.get("ref") else e

inclusive, leaf, per_second = collections.Counter(), collections.Counter(), collections.Counter()
total = 0
for row in root.iter("row"):
    thread = get(row.find("thread"))
    if thread is None or "Main Thread" not in (thread.get("fmt") or "") or app not in (thread.get("fmt") or ""):
        continue
    weight = int(get(row.find("weight")).text) / 1e6  # ms
    when = int(get(row.find("sample-time")).text) / 1e9
    backtrace = get(row.find("backtrace"))
    frames = [(get(f).get("name") or get(f).get("addr") or "?") for f in backtrace.findall("frame")] if backtrace is not None else []
    total += weight
    per_second[int(when)] += weight
    if frames:
        leaf[frames[0]] += weight
    for name in set(frames):
        inclusive[name] += weight

print(f"main thread busy: {total:.0f} ms")
print("busy ms per second:", " ".join(f"{s}s:{per_second[s]:.0f}" for s in sorted(per_second)))
print("\n-- most time inside (inclusive) --")
for name, ms in inclusive.most_common(60):
    print(f"{ms:8.0f} ms  {name[:150]}")
print("\n-- most time at the top of the stack (self) --")
for name, ms in leaf.most_common(30):
    print(f"{ms:8.0f} ms  {name[:150]}")
