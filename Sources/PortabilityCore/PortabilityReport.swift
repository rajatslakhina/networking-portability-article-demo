import Foundation

/// What the analyzer produces. Everything here is derived, nothing is asserted.
public struct PortabilityReport: Sendable {

    /// What the team thinks its coupling is.
    public let declaredSeams: Int
    /// Merged, live usage records.
    public let usages: [CapabilityUsage]
    /// Distinct capabilities the app actually consumes.
    public let effectiveSurface: Int
    /// Total call sites that reach around the abstraction.
    public let bypassSiteCount: Int
    public let migrationCost: Double
    public let verdict: MigrationVerdict

    public init(
        declaredSeams: Int,
        usages: [CapabilityUsage],
        effectiveSurface: Int,
        bypassSiteCount: Int,
        migrationCost: Double,
        verdict: MigrationVerdict
    ) {
        self.declaredSeams = declaredSeams
        self.usages = usages
        self.effectiveSurface = effectiveSurface
        self.bypassSiteCount = bypassSiteCount
        self.migrationCost = migrationCost
        self.verdict = verdict
    }

    /// Effective surface divided by declared seams — the gap between the story and
    /// the code. `nil` when no seam was declared, rather than a division by zero.
    public var surfaceRatio: Double? {
        guard declaredSeams > 0 else { return nil }
        return Double(effectiveSurface) / Double(declaredSeams)
    }

    /// Cost split by layer, so the platform-service share is visible rather than
    /// buried in one total.
    public func costByClass(using analyzer: PortabilityAnalyzer = .init()) -> [PortabilityClass: Double] {
        var result: [PortabilityClass: Double] = [:]
        for usage in usages {
            result[usage.capability.portability, default: 0] += analyzer.contribution(of: usage)
        }
        return result
    }

    /// Bounds-checked accessor for UI list rendering.
    public func usage(at index: Int) -> CapabilityUsage? {
        guard usages.indices.contains(index) else { return nil }
        return usages[index]
    }

    public func capabilities(in portabilityClass: PortabilityClass) -> [CapabilityUsage] {
        usages.filter { $0.capability.portability == portabilityClass }
    }

    /// The one line worth pasting into a design doc.
    public func summaryLine() -> String {
        let ratio = surfaceRatio.map { String(format: "%.0fx", $0) } ?? "n/a"
        return "MEASURED — declared seams: \(declaredSeams) · effective surface: "
            + "\(effectiveSurface) capabilities (\(ratio)) · bypass sites: \(bypassSiteCount) · "
            + "cost: \(String(format: "%.1f", migrationCost)) · verdict: \(verdict.label)"
    }
}
