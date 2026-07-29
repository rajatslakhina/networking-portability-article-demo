import Foundation

/// Tunable weights. Exposed so a team can recalibrate against their own migration
/// instead of inheriting my guesses — the ordering claim is the durable part, the
/// exact numbers are not.
public struct CostModel: Sendable, Equatable {
    /// Sub-linear scaling on call sites: the fortieth call site genuinely is
    /// cheaper to move than the first, because by then you have a pattern.
    public var siteScaling: @Sendable (Int) -> Double

    public static let `default` = CostModel { siteCount in
        1 + log2(1 + Double(max(0, siteCount)))
    }

    public init(siteScaling: @escaping @Sendable (Int) -> Double) {
        self.siteScaling = siteScaling
    }

    public static func == (lhs: CostModel, rhs: CostModel) -> Bool {
        // Compared structurally at a few sample points; closures aren't Equatable.
        [0, 1, 5, 40].allSatisfy { lhs.siteScaling($0) == rhs.siteScaling($0) }
    }
}

/// Turns an inventory of capability usage into a migration report.
///
/// The whole point: the number a team quotes ("we have one HTTP client protocol,
/// so we're portable") and the number that decides the migration are different
/// numbers, and only one of them is computed from what the app actually does.
public struct PortabilityAnalyzer: Sendable {

    public var costModel: CostModel

    public init(costModel: CostModel = .default) {
        self.costModel = costModel
    }

    /// - Parameters:
    ///   - declaredSeams: how many transport abstractions the team believes it has.
    ///     Usually 1. Negative values are clamped to 0.
    ///   - usages: the raw inventory. Duplicates are merged worst-severity-wins.
    public func analyze(declaredSeams: Int, usages: [CapabilityUsage]) -> PortabilityReport {
        let seams = max(0, declaredSeams)
        let merged = Self.merge(usages)
        let live = merged.filter(\.isLive)

        let cost = live.reduce(into: 0.0) { total, usage in
            total += contribution(of: usage)
        }

        let distinctCapabilities = Set(live.map(\.capability.id))
        let bypassSites = live
            .filter { $0.routing == .bypassesSeam }
            .reduce(0) { $0 + $1.siteCount }

        return PortabilityReport(
            declaredSeams: seams,
            usages: live,
            effectiveSurface: distinctCapabilities.count,
            bypassSiteCount: bypassSites,
            migrationCost: cost,
            verdict: verdict(for: live, cost: cost)
        )
    }

    /// Cost of a single merged usage record.
    public func contribution(of usage: CapabilityUsage) -> Double {
        guard usage.isLive else { return 0 }
        return usage.capability.portability.migrationWeight
            * costModel.siteScaling(usage.siteCount)
            * usage.routing.costMultiplier
            * usage.fallback.costDiscount
    }

    // MARK: - Merging

    /// Duplicate records for the same capability in the same module collapse to
    /// one. Site counts add; routing and fallback take the *worst* value, because
    /// a capability with one unplanned bypass site is an unplanned bypass no
    /// matter how well the other nine sites behave.
    static func merge(_ usages: [CapabilityUsage]) -> [CapabilityUsage] {
        var byKey: [String: CapabilityUsage] = [:]
        var order: [String] = []

        for usage in usages {
            let key = usage.id
            guard let existing = byKey[key] else {
                byKey[key] = usage
                order.append(key)
                continue
            }
            byKey[key] = CapabilityUsage(
                capability: existing.capability,
                module: existing.module,
                siteCount: existing.siteCount + usage.siteCount,
                routing: existing.routing.severity >= usage.routing.severity
                    ? existing.routing : usage.routing,
                fallback: existing.fallback.severity >= usage.fallback.severity
                    ? existing.fallback : usage.fallback
            )
        }
        return order.compactMap { byKey[$0] }
    }

    // MARK: - Policy

    /// The executable version of the argument.
    ///
    /// A platform service with no fallback plan blocks the migration outright.
    /// It does not matter how clean the protocol above it looks, because the
    /// protocol was never what made it portable.
    func verdict(for usages: [CapabilityUsage], cost: Double) -> MigrationVerdict {
        var hardBlockers: [String] = []
        var stagingBlockers: [String] = []

        for usage in usages where usage.capability.portability == .platformService {
            switch usage.fallback {
            case .none:
                hardBlockers.append(
                    "\(usage.capability.name) — load-bearing in \(usage.module) "
                    + "(\(usage.siteCount) site\(usage.siteCount == 1 ? "" : "s")) with no fallback plan."
                )
            case .documented:
                stagingBlockers.append(
                    "\(usage.capability.name) — plan written but not built in \(usage.module)."
                )
            case .implemented:
                continue
            }
        }

        for usage in usages
        where usage.routing == .bypassesSeam && usage.capability.portability != .currencyType {
            stagingBlockers.append(
                "\(usage.capability.name) — \(usage.siteCount) site"
                + "\(usage.siteCount == 1 ? "" : "s") in \(usage.module) reach around the abstraction."
            )
        }

        if !hardBlockers.isEmpty {
            return .blocked(cost: cost, reasons: hardBlockers)
        }
        if !stagingBlockers.isEmpty {
            return .stageable(cost: cost, blockers: stagingBlockers)
        }
        return .cheap(cost: cost)
    }
}
