import Foundation

// Muscle ranks (lib/muscle-ranks.ts): each muscle's rank from its strongest ranked lift, as an estimated one-rep max
// relative to bodyweight. A rough guide for general lifters, not a competitive table.

public enum Muscle: String, CaseIterable, Sendable { case chest = "Chest", back = "Back", shoulders = "Shoulders", arms = "Arms", legs = "Legs" }

public enum Ranks {
    public static let names = ["Starter", "Novice", "Solid", "Strong", "Elite"]

    struct Lift {
        let muscle: Muscle
        let lift: String
        let match: NSRegularExpression
        /// Bodyweight multiples that reach Novice, Solid, Strong and Elite.
        let at: [Double]
        /// The weight is one side's (dumbbells, cable raises).
        var perSide = false
        /// The movement only exists on a machine or cable.
        var machine = false
    }

    private static func lift(_ muscle: Muscle, _ name: String, _ pattern: String, _ at: [Double], perSide: Bool = false, machine: Bool = false) -> Lift {
        Lift(muscle: muscle, lift: name, match: try! NSRegularExpression(pattern: pattern), at: at, perSide: perSide, machine: machine)
    }

    // The website's table, in its order: the first match wins, so specific movements come before generic ones.
    static let lifts: [Lift] = [
        lift(.legs, "Calf raise", #"\bcalf|\bcalves"#, [1.0, 1.75, 2.5, 3.5]),
        lift(.shoulders, "Rear delt", #"\brear[ -]?delt|\bface ?pull|\breverse (fly|flye|pec)"#, [0.08, 0.15, 0.25, 0.38], perSide: true),
        lift(.legs, "Leg curl", #"\b(leg|hamstring) curl|\b(lying|seated) (leg )?curl machine"#, [0.3, 0.5, 0.75, 1.05], machine: true),
        lift(.legs, "Leg extension", #"\b(leg|quad) extension"#, [0.4, 0.7, 1.0, 1.4], machine: true),
        lift(.legs, "Romanian deadlift", #"\b(romanian|rdl|sldl|stiff[ -]?leg(ged)?)\b"#, [0.5, 0.85, 1.25, 1.8]),
        lift(.legs, "Leg press", #"\bleg press"#, [0.9, 1.7, 2.5, 3.6], machine: true),
        lift(.legs, "Hip thrust", #"\bhip thrust|\bglute bridge"#, [0.6, 1.1, 1.6, 2.3]),
        lift(.legs, "Hack squat", #"\bhack squat|\bpendulum squat|\bbelt squat"#, [0.7, 1.2, 1.7, 2.4], machine: true),
        lift(.legs, "Barbell lunge", #"\bbarbell\b.*\b(lunge|split squat|step[ -]?up)"#, [0.25, 0.45, 0.7, 1.0]),
        lift(.legs, "Lunge", #"\b(lunge|split squat|step[ -]?up)"#, [0.1, 0.2, 0.35, 0.5], perSide: true),
        lift(.legs, "Goblet squat", #"\bgoblet squat"#, [0.15, 0.3, 0.45, 0.65]),
        lift(.legs, "Squat", #"^(?!.*\b(split|goblet|sissy|jump|bodyweight|pistol|zombie|bulgarian)\b).*\bsquat"#, [0.6, 1.0, 1.4, 2.0]),
        lift(.back, "Deadlift", #"\bdeadlift"#, [0.8, 1.25, 1.7, 2.4]),
        lift(.back, "Dumbbell shrug", #"\b(dumbbell|db)\b.*\bshrug"#, [0.3, 0.5, 0.75, 1.1], perSide: true),
        lift(.back, "Shrug", #"\bshrug"#, [0.6, 1.0, 1.5, 2.2]),
        lift(.back, "Lat isolation", #"\bkeenan"#, [0.2, 0.35, 0.55, 0.8], machine: true),
        lift(.back, "Lat isolation", #"\bpull ?-?over|\bstraight[ -]arm|\blat (prayer|extension)"#, [0.2, 0.35, 0.55, 0.8]),
        lift(.shoulders, "Upright row", #"\bupright row"#, [0.3, 0.5, 0.7, 1.0]),
        lift(.back, "Lat pulldown", #"\bpull ?-?down"#, [0.4, 0.65, 0.9, 1.25], machine: true),
        lift(.back, "Dumbbell row", #"\b(dumbbell|db|kroc)\b.*\brow"#, [0.2, 0.35, 0.5, 0.75], perSide: true),
        lift(.back, "Barbell row", #"\b(barbell|bent[ -]over|pendlay|yates)\b.*\brow"#, [0.4, 0.65, 0.9, 1.3]),
        lift(.back, "Row", #"\brows?\b"#, [0.4, 0.65, 0.9, 1.25]),
        lift(.shoulders, "Lateral raise", #"\b(lateral|side|lat|y)[ -]raise"#, [0.05, 0.09, 0.14, 0.21], perSide: true),
        lift(.shoulders, "Dumbbell shoulder press", #"\b(dumbbell|db)\b.*\b(shoulder|overhead) press|\barnold press"#, [0.12, 0.2, 0.3, 0.42], perSide: true),
        lift(.shoulders, "Machine shoulder press", #"\b(machine|smith|cable)\b.*\b(shoulder|overhead) press|\b(shoulder|overhead) press machine"#, [0.4, 0.65, 0.95, 1.35]),
        lift(.shoulders, "Overhead press", #"\b(overhead|military|shoulder|push|z) press|^ohp\b"#, [0.3, 0.45, 0.65, 0.9]),
        lift(.chest, "Chest fly", #"\b(fly|flye|flyes|flies)\b|\bpec ?dec|\bcable crossover(?!.*curl)"#, [0.25, 0.45, 0.7, 1.0]),
        lift(.chest, "Incline press", #"\bincline\b.*\b(bench|press)"#, [0.35, 0.55, 0.8, 1.15]),
        lift(.chest, "Dumbbell bench press", #"\b(dumbbell|db)\b.*\b(bench|chest) press"#, [0.15, 0.25, 0.38, 0.55], perSide: true),
        lift(.chest, "Chest press", #"\b(machine|chest|smith) press|\bpress machine"#, [0.5, 0.85, 1.2, 1.7]),
        lift(.chest, "Bench press", #"\b(bench|floor) press|^bench$"#, [0.45, 0.7, 1.0, 1.4]),
        lift(.arms, "Triceps pushdown", #"\bpush ?-?downs?\b"#, [0.2, 0.35, 0.5, 0.75], machine: true),
        lift(.arms, "Triceps extension", #"\btriceps?\b|\bskull ?crusher|\b(french|jm) press|\bkickback"#, [0.12, 0.22, 0.35, 0.5]),
        lift(.arms, "Reverse curl", #"\breverse(-grip)? curl"#, [0.12, 0.22, 0.35, 0.5]),
        lift(.arms, "Dumbbell curl", #"\b(dumbbell|db|hammer|concentration)\b.*\bcurl"#, [0.08, 0.15, 0.24, 0.35], perSide: true),
        lift(.arms, "Machine curl", #"\b(machine|preacher)\b.*\bcurl|\bcurl machine"#, [0.2, 0.35, 0.55, 0.8]),
        lift(.arms, "Curl", #"\bcurls?\b"#, [0.18, 0.33, 0.5, 0.7]),
    ]
    /// Core, forearm and bodyweight-only work doesn't compare well against bodyweight, so it never ranks.
    static let unranked = try! NSRegularExpression(pattern: #"\b(crunch|sit[ -]?ups?|plank|leg raise|knee raise|ab wheel|abs?|russian twist|oblique|wood ?chop|pallof|wrist (curl|extension|roller)|dead ?hang|glute (push ?-?down|kickback))\b"#)
    /// Machine and cable stacks read heavier than the real load, so their weight counts at 75%; naming free weights
    /// overrides it.
    static let freeWeight = try! NSRegularExpression(pattern: #"\b(dumbbell|db|barbell|kettlebell|ez[ -]?bar)\b"#)
    static let machine = try! NSRegularExpression(pattern: #"\b(machine|cable|smith|pulley|lever|pec ?dec|selectorized|plate[ -]loaded)\b"#)
    static let machineLoad = 0.75

    static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The ranked lift an exercise name counts as, if any.
    static func lift(for name: String) -> Lift? {
        let key = name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if matches(unranked, key) { return nil }
        return lifts.first { matches($0.match, key) }
    }

    /// Epley's estimate; beyond 12 reps it overstates strength, so those sets don't rank.
    static func oneRepMax(_ kg: Double, _ reps: Int) -> Double { reps == 1 ? kg : kg * (1 + Double(reps) / 30) }

    /// Position on the ladder: 0–1 is Starter, 1–2 Novice, …, 4 or more Elite.
    static func ladder(_ ratio: Double, _ at: [Double]) -> Double {
        if ratio < at[0] { return ratio / at[0] }
        for i in 1..<at.count where ratio < at[i] { return Double(i) + (ratio - at[i - 1]) / (at[i] - at[i - 1]) }
        return Double(at.count)
    }
}

public struct MuscleRank: Equatable, Sendable {
    public let muscle: Muscle
    /// Index into Ranks.names.
    public let rank: Int
    /// 0–1 of the way to the next rank (1 at Elite).
    public let progress: Double
    public let best: (exercise: String, lift: String, kg: Double, reps: Int)?
    /// The weight that reaches the next rank on that lift at the same reps (none at Elite).
    public let next: (kg: Double, reps: Int)?

    public var name: String { Ranks.names[rank] }

    public static func == (a: MuscleRank, b: MuscleRank) -> Bool {
        a.muscle == b.muscle && a.rank == b.rank && a.progress == b.progress && a.best?.exercise == b.best?.exercise
            && a.best?.kg == b.best?.kg && a.next?.kg == b.next?.kg
    }
}

extension Array where Element == Session {
    /// Each muscle's rank from its strongest ranked lift, relative to bodyweight (kg).
    public func muscleRanks(bodyweight: Double) -> [MuscleRank] {
        var best: [Muscle: (score: Double, at: [Double], scale: Double, exercise: String, lift: String, kg: Double, reps: Int)] = [:]
        for session in self { for exercise in session.exercises {
            guard let lift = Ranks.lift(for: exercise.name) else { continue }
            let name = exercise.name.lowercased()
            for set in exercise.sets {
                guard set.done, let kg = set.kg, kg > 0, let reps = set.reps, reps > 0, reps <= 12 else { continue }
                let sides: Double = !lift.perSide && (set.side != nil || Exercise.firstSide(for: name) != nil) ? 2 : 1
                let load = !Ranks.matches(Ranks.freeWeight, name) && (lift.machine || Ranks.matches(Ranks.machine, name)) ? Ranks.machineLoad : 1
                let score = Ranks.ladder(Ranks.oneRepMax(kg, reps) * sides * load / bodyweight, lift.at)
                if score > (best[lift.muscle]?.score ?? -1) {
                    best[lift.muscle] = (score, lift.at, sides * load, exercise.name, lift.lift, kg, reps)
                }
            }
        } }
        return Muscle.allCases.map { muscle in
            guard let top = best[muscle] else { return MuscleRank(muscle: muscle, rank: 0, progress: 0, best: nil, next: nil) }
            let rank = Swift.min(Ranks.names.count - 1, Int(top.score.rounded(.down)))
            let elite = rank == Ranks.names.count - 1
            // The weight that reaches the next rank, rounded up to the next 0.5 kg so lifting it really does. None at
            // Elite: there is no rank above it (at[] holds the four thresholds above Starter).
            let next: (kg: Double, reps: Int)? = elite ? nil : (((top.at[rank] * bodyweight / top.scale / Ranks.oneRepMax(1, top.reps)) * 2).rounded(.up) / 2, top.reps)
            return MuscleRank(muscle: muscle, rank: rank, progress: elite ? 1 : top.score - Double(rank),
                              best: (top.exercise, top.lift, top.kg, top.reps), next: next)
        }
    }
}
