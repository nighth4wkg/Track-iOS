# The demo training (demo-data.py on stdin) with every split made 12 exercises of 4 sets, as a full day's workout:
# the same as UITests/PerfTour.swift's bigSeed, for profile.yml.
import json, sys

data = json.load(sys.stdin)
names = ["Bench Press", "Lat pulldown", "Overhead Press", "Barbell curl", "Back squat", "Romanian deadlift",
         "Incline dumbbell press", "Seated cable row", "Lateral raise", "Triceps pushdown", "Leg press", "Calf raise"]
for s, split in enumerate(data["splits"]):
    split["exercises"] = [{"id": f"p{s}e{e}", "name": name,
                           "sets": [{"id": f"p{s}e{e}s{k}", "kg": 40, "reps": 8, "rir": 2, "done": False} for k in range(4)]}
                          for e, name in enumerate(names)]
json.dump(data, sys.stdout)
