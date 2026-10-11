import Foundation
import ThicketCore

public enum SessionOutcome: Equatable {
    case none
    case roundWon(round: Int)
    case campaignComplete
    case roundLost(LossReason)
    case trialComplete(ticks: Int)
    case lessonComplete
    case versusOver(winner: Int)
}

/// Mode flow on top of the simulation: which round comes next, Time Trial clocks,
/// lesson goals, what gets recorded in the save file. Platform independent.
public struct SessionModel {
    public private(set) var kind: SessionKind
    public private(set) var state: GameState
    public private(set) var versus: VersusMatch?
    public private(set) var outcome: SessionOutcome = .none
    public private(set) var recorded = false

    public init(kind: SessionKind, seed: UInt64 = 1) {
        self.kind = kind
        switch kind {
        case let .campaign(round):
            state = GameState(config: .campaign(round), seed: roundSeed(round))
        case .endless:
            state = GameState(config: .endless(), seed: seed)
        case let .timeTrial(trailID, index, _):
            let trail = TimeTrial.all.first { $0.id == trailID } ?? TimeTrial.all[0]
            let round = trail.rounds[min(index, trail.rounds.count - 1)]
            state = GameState(config: .campaign(round), seed: roundSeed(round))
        case let .lesson(id):
            let lesson = Lesson.all.first { $0.id == id } ?? Lesson.all[0]
            state = lesson.makeState()
        case .versus:
            let match = VersusMatch(seed: seed)
            versus = match
            state = match.players[0]
        }
    }

    public init(resuming s: SuspendedSession) {
        self.init(kind: s.kind)
        if let st = s.state { state = st }
        if let v = s.versus {
            versus = v
            state = v.players[0]
        }
    }

    public var snapshot: SuspendedSession {
        SuspendedSession(kind: kind, state: versus == nil ? state : nil, versus: versus)
    }

    public var isFinished: Bool { outcome != .none }

    public var lesson: Lesson? {
        if case let .lesson(id) = kind { return Lesson.all.first { $0.id == id } }
        return nil
    }

    public var trail: TimeTrial? {
        if case let .timeTrial(id, _, _) = kind { return TimeTrial.all.first { $0.id == id } }
        return nil
    }

    /// Total Time Trial clock including earlier rounds of the trail.
    public var trialTicks: Int {
        if case let .timeTrial(_, _, elapsed) = kind { return elapsed + state.tick }
        return state.tick
    }

    public var title: String {
        switch kind {
        case let .campaign(round): return "Round \(round)"
        case .endless: return "Endless"
        case let .timeTrial(_, index, _):
            return "\(trail?.name ?? "Trial") \(index + 1)/\(trail?.rounds.count ?? 0)"
        case .lesson: return lesson?.title ?? "Lesson"
        case .versus: return "Versus"
        }
    }

    /// Advances one 60 Hz tick. `inputs[i]` is player i's input.
    @discardableResult
    public mutating func step(_ inputs: [InputFrame]) -> [[GameEvent]] {
        guard outcome == .none else { return [[]] }
        if var match = versus {
            let events = match.step(inputs)
            versus = match
            state = match.players[0]
            if let w = match.winner { outcome = .versusOver(winner: w) }
            return events
        }
        let events = state.step(inputs.first ?? .none)
        if let lesson, lesson.isComplete(state, events: events) {
            outcome = .lessonComplete
        } else {
            switch state.status {
            case .playing: break
            case let .lost(reason): outcome = .roundLost(reason)
            case .won:
                switch kind {
                case let .campaign(round):
                    outcome = round >= RoundConfig.campaignRounds ? .campaignComplete : .roundWon(round: round)
                case let .timeTrial(_, index, _):
                    if index + 1 >= (trail?.rounds.count ?? 1) {
                        outcome = .trialComplete(ticks: trialTicks)
                    } else {
                        outcome = .roundWon(round: state.config.round)
                    }
                case .lesson:
                    outcome = .lessonComplete
                default:
                    outcome = .roundWon(round: state.config.round)
                }
            }
        }
        return [events]
    }

    /// Writes the outcome into the save data once. Returns true for a new record
    /// (best time, best endless score).
    @discardableResult
    public mutating func record(into save: inout SaveData) -> Bool {
        guard outcome != .none, !recorded else { return false }
        recorded = true
        switch (kind, outcome) {
        case let (.campaign(round), .roundWon), let (.campaign(round), .campaignComplete):
            save.campaign.record(round: round, won: true, score: state.score)
            save.bestChain = max(save.bestChain, state.maxChain)
        case let (.campaign(round), .roundLost):
            save.campaign.record(round: round, won: false, score: state.score)
        case let (.timeTrial(trail, _, _), .trialComplete(ticks)):
            return save.recordTime(trail: trail, ticks: ticks)
        case (.endless, .roundLost):
            return save.recordEndless(score: state.score, chain: state.maxChain)
        case let (.lesson(id), .lessonComplete):
            save.lessonsCompleted.insert(id)
        default:
            break
        }
        return false
    }

    /// What to play after this session ends (nil = back to the menu).
    public var next: SessionKind? {
        switch (kind, outcome) {
        case let (.campaign(round), .roundWon):
            return CampaignProgress.next(after: round).map { .campaign(round: $0) }
        case let (.campaign(round), .roundLost):
            return .campaign(round: round)
        case let (.timeTrial(trail, index, elapsed), .roundWon):
            return .timeTrial(trail: trail, index: index + 1, elapsedTicks: elapsed + state.tick)
        case let (.timeTrial(trail, _, _), .roundLost), let (.timeTrial(trail, _, _), .trialComplete):
            return .timeTrial(trail: trail, index: 0, elapsedTicks: 0)
        case let (.lesson(id), .lessonComplete):
            guard let i = Lesson.all.firstIndex(where: { $0.id == id }), i + 1 < Lesson.all.count else { return nil }
            return .lesson(id: Lesson.all[i + 1].id)
        case (.lesson, .roundLost):
            return kind
        case (.endless, _), (.versus, _):
            return kind
        default:
            return nil
        }
    }
}
