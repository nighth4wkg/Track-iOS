import Foundation

// Muscle ranks (lib/muscle-ranks.ts): each muscle group's rank from its strongest ranked lift, as an estimated one-rep
// max relative to bodyweight. A rough guide for general lifters, not a competitive table. Which lift a name counts as,
// and how its weight reads, comes from LiftTable.

/// The rank groups. LiftTable.groups holds the same names in the same order (RankTests checks it).
public enum Muscle: String, CaseIterable, Sendable { case chest = "Chest", back = "Back", shoulders = "Shoulders", arms = "Arms", legs = "Legs" }

/// How a set's weight reads: plain weight, added to bodyweight, or assistance taken off it.
public enum LoadKind: String, Sendable { case weight, added, assisted }

public enum Ranks {
    public static let names = ["Starter", "Novice", "Solid", "Strong", "Elite"]

    /// Epley's estimate; beyond the table's maxReps it overstates strength, so those sets don't rank.
    static func oneRepMax(_ kg: Double, _ reps: Int) -> Double { reps == 1 ? kg : kg * (1 + Double(reps) / 30) }

    /// Position on the ladder: 0–1 is Starter, 1–2 Novice, …, 4 or more Elite.
    static func ladder(_ ratio: Double, _ at: [Double]) -> Double {
        if ratio < at[0] { return ratio / at[0] }
        for i in 1..<at.count where ratio < at[i] { return Double(i) + (ratio - at[i - 1]) / (at[i] - at[i - 1]) }
        return Double(at.count)
    }

    /// The lift a name ranks on, with its standard, group and load rules; nil when it never ranks.
    static func ranked(_ name: String, choices: [String: String]) -> (lift: Lift, at: [Double], group: Muscle, oneSided: Bool, sign: Double, scale: Double)? {
        guard let lift = LiftTable.lift(for: name, choices: choices).lift, let at = lift.at,
              let group = lift.group.flatMap(Muscle.init(rawValue:)) else { return nil }
        let load = LiftTable.load(for: lift, name: name)
        return (lift, at, group, load.oneSided, load.sign, load.scale)
    }
}

public struct MuscleRank: Equatable, Sendable {
    public let muscle: Muscle
    /// Index into Ranks.names.
    public let rank: Int
    /// 0–1 of the way to the next rank (1 at Elite).
    public let progress: Double
    public let best: (exercise: String, lift: String, kg: Double, reps: Int, kind: LoadKind)?
    /// The weight that reaches the next rank on that lift at the same reps (none at Elite).
    public let next: (kg: Double, reps: Int)?

    public var name: String { Ranks.names[rank] }

    public static func == (a: MuscleRank, b: MuscleRank) -> Bool {
        a.muscle == b.muscle && a.rank == b.rank && a.progress == b.progress && a.best?.exercise == b.best?.exercise
            && a.best?.kg == b.best?.kg && a.best?.kind == b.best?.kind && a.next?.kg == b.next?.kg
    }
}

extension Array where Element == Session {
    /// Each muscle group's rank from its strongest ranked lift, relative to bodyweight (kg), with the user's
    /// "counts as" choices (Settings.lifts).
    public func muscleRanks(bodyweight: Double, choices: [String: String] = [:]) -> [MuscleRank] {
        typealias Top = (score: Double, at: [Double], base: Double, sign: Double, scale: Double, sides: Double,
                         best: (exercise: String, lift: String, kg: Double, reps: Int, kind: LoadKind))
        var best: [Muscle: Top] = [:]
        // Each name is read once: the same exercise repeats across workouts.
        var names: [String: (lift: Lift, at: [Double], group: Muscle, oneSided: Bool, sign: Double, scale: Double)?] = [:]
        for session in self { for exercise in session.exercises {
            if names[exercise.name] == nil { names[exercise.name] = .some(Ranks.ranked(exercise.name, choices: choices)) }
            guard let found = names[exercise.name] ?? nil else { continue }
            let lift = found.lift
            let base = (lift.bodyweight ?? 0) * bodyweight
            for set in exercise.sets {
                guard set.done, let kg = set.kg, let reps = set.reps, reps > 0, reps <= LiftTable.maxReps,
                      lift.bodyweight != nil || kg > 0 else { continue }
                // Scores compare across lifts by how far through the ladder of their own standards they are.
                let sides: Double = lift.perSide != true && (set.side != nil || found.oneSided) ? 2 : 1
                let load = (base + found.sign * kg * found.scale) * sides
                guard load > 0 else { continue }
                let score = Ranks.ladder(Ranks.oneRepMax(load, reps) / bodyweight, found.at)
                if score > (best[found.group]?.score ?? -1) {
                    let kind: LoadKind = lift.bodyweight == nil ? .weight : found.sign < 0 ? .assisted : .added
                    best[found.group] = (score, found.at, base, found.sign, found.scale, sides, (exercise.name, lift.name, kg, reps, kind))
                }
            }
        } }
        return Muscle.allCases.map { muscle in
            guard let top = best[muscle] else { return MuscleRank(muscle: muscle, rank: 0, progress: 0, best: nil, next: nil) }
            let rank = Swift.max(0, Swift.min(Ranks.names.count - 1, Int(top.score.rounded(.down))))
            let elite = rank == Ranks.names.count - 1
            return MuscleRank(muscle: muscle, rank: rank, progress: elite ? 1 : top.score - Double(rank), best: top.best,
                              next: elite ? nil : Self.nextWeight(top.at[rank], top: (top.base, top.sign, top.scale, top.sides), reps: top.best.reps, bodyweight: bodyweight))
        }
    }

    /// The weight that reaches the next rank at the same reps, to the next 0.5 kg so lifting it really does: more weight,
    /// or less assistance (none when even bodyweight alone falls short; the next step is then added weight).
    static func nextWeight(_ target: Double, top: (base: Double, sign: Double, scale: Double, sides: Double), reps: Int, bodyweight: Double) -> (kg: Double, reps: Int)? {
        let perSide = target * bodyweight / Ranks.oneRepMax(1, reps) / top.sides
        let kg = top.sign * (perSide - top.base) / top.scale
        if top.sign > 0 { return ((kg * 2).rounded(.up) / 2, reps) }
        return kg < 0 ? nil : ((kg * 2).rounded(.down) / 2, reps)
    }
}
