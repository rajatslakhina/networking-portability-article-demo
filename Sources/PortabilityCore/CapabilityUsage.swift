import Foundation

/// How a call site reaches a capability.
public enum Routing: String, Sendable, Codable, CaseIterable {
    /// Reached through the app's own transport abstraction. Portable-ish: there is
    /// exactly one place to change.
    case throughSeam
    /// Reached by touching URLSession, URLSessionConfiguration, a delegate callback,
    /// or a shared singleton directly. The abstraction does not know this exists.
    case bypassesSeam

    /// Bypasses cost more because migrating them means finding them first.
    public var costMultiplier: Double {
        switch self {
        case .throughSeam: return 1.0
        case .bypassesSeam: return 2.5
        }
    }

    /// Ordering used by worst-severity-wins merging.
    var severity: Int {
        switch self {
        case .throughSeam: return 0
        case .bypassesSeam: return 1
        }
    }
}

/// What the team has actually decided to do if this capability disappears.
public enum FallbackPlan: Sendable, Codable, Hashable {
    /// Nobody has decided anything. This is the state that blocks migrations.
    case none
    /// Written down and agreed, not built.
    case documented(String)
    /// Built and shipping today.
    case implemented(String)

    /// A real plan discounts the cost of moving. An imaginary one does not.
    public var costDiscount: Double {
        switch self {
        case .none: return 1.0
        case .documented: return 0.7
        case .implemented: return 0.35
        }
    }

    /// Ordering used by worst-severity-wins merging: the weakest plan across
    /// duplicate records is the one that survives, because the weakest site is
    /// the one that will break.
    var severity: Int {
        switch self {
        case .implemented: return 0
        case .documented: return 1
        case .none: return 2
        }
    }

    public var summary: String {
        switch self {
        case .none: return "No plan"
        case .documented(let text): return "Documented: \(text)"
        case .implemented(let text): return "Implemented: \(text)"
        }
    }
}

/// One module's dependence on one capability.
public struct CapabilityUsage: Sendable, Codable, Hashable, Identifiable {

    public let capability: TransportCapability
    public let module: String
    /// Number of call sites. Negative inputs are clamped to zero rather than
    /// trapping, so a bad CSV row degrades instead of crashing the report.
    public let siteCount: Int
    public let routing: Routing
    public let fallback: FallbackPlan

    public var id: String { "\(capability.id)|\(module)" }

    public init(
        capability: TransportCapability,
        module: String,
        siteCount: Int,
        routing: Routing,
        fallback: FallbackPlan
    ) {
        self.capability = capability
        self.module = module
        self.siteCount = max(0, siteCount)
        self.routing = routing
        self.fallback = fallback
    }

    /// True when this record contributes to the effective surface. A capability
    /// declared with zero call sites is inventory noise, not a dependency.
    public var isLive: Bool { siteCount > 0 }
}
