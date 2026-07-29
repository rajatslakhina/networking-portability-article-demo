import Foundation

/// The output of the policy, not of the arithmetic.
///
/// Cost tells you how big the job is. The verdict tells you whether you are
/// allowed to start — and those are different questions.
public enum MigrationVerdict: Sendable, Equatable {

    /// Nothing in the inventory resists moving.
    case cheap(cost: Double)

    /// Movable, but only after named work lands first.
    case stageable(cost: Double, blockers: [String])

    /// At least one platform service is load-bearing with no plan behind it.
    /// No amount of protocol abstraction changes this.
    case blocked(cost: Double, reasons: [String])

    public var cost: Double {
        switch self {
        case .cheap(let c), .stageable(let c, _), .blocked(let c, _): return c
        }
    }

    public var label: String {
        switch self {
        case .cheap: return "CHEAP"
        case .stageable: return "STAGEABLE"
        case .blocked: return "BLOCKED"
        }
    }

    /// Human-readable lines behind the verdict. Empty for `.cheap`.
    public var notes: [String] {
        switch self {
        case .cheap: return []
        case .stageable(_, let blockers): return blockers
        case .blocked(_, let reasons): return reasons
        }
    }
}
