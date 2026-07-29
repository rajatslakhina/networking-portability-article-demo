import Foundation

/// A deliberately ordinary inventory: one shopping app with a checkout flow, a
/// media downloader, an auth module, and analytics. Every entry is the kind of
/// thing that is genuinely in a production app and genuinely not HTTP.
public enum SampleInventory {

    public static let declaredSeams = 1

    public static let usages: [CapabilityUsage] = [
        CapabilityUsage(
            capability: .requestResponseValues, module: "APIClient",
            siteCount: 61, routing: .throughSeam,
            fallback: .implemented("swift-http-types values already cross the seam")
        ),
        CapabilityUsage(
            capability: .jsonCoding, module: "APIClient",
            siteCount: 48, routing: .throughSeam,
            fallback: .implemented("Codable, transport-agnostic")
        ),
        CapabilityUsage(
            capability: .urlAndQueryEncoding, module: "APIClient",
            siteCount: 22, routing: .throughSeam,
            fallback: .implemented("URLComponents builder is ours")
        ),
        CapabilityUsage(
            capability: .tlsTrustEvaluation, module: "Networking",
            siteCount: 2, routing: .bypassesSeam,
            fallback: .documented("pin set moves to the new stack's trust callback")
        ),
        CapabilityUsage(
            capability: .http2Multiplexing, module: "FeedSync",
            siteCount: 4, routing: .throughSeam,
            fallback: .documented("assumed, never verified under load")
        ),
        CapabilityUsage(
            capability: .webSocketFraming, module: "LiveOrderTracking",
            siteCount: 3, routing: .bypassesSeam,
            fallback: .documented("reconnect policy is ours, framing is theirs")
        ),
        CapabilityUsage(
            capability: .sharedCookieStorage, module: "Checkout",
            siteCount: 5, routing: .bypassesSeam,
            fallback: .none
        ),
        CapabilityUsage(
            capability: .systemCredentialStore, module: "Auth",
            siteCount: 4, routing: .bypassesSeam,
            fallback: .none
        ),
        CapabilityUsage(
            capability: .backgroundTransfer, module: "MediaDownloader",
            siteCount: 7, routing: .bypassesSeam,
            fallback: .none
        ),
        CapabilityUsage(
            capability: .waitsForConnectivity, module: "MediaDownloader",
            siteCount: 2, routing: .bypassesSeam,
            fallback: .documented("retry loop with reachability, not yet built")
        ),
        CapabilityUsage(
            capability: .cellularPolicy, module: "MediaDownloader",
            siteCount: 3, routing: .bypassesSeam,
            fallback: .documented("expose as a per-request policy on the seam")
        ),
        CapabilityUsage(
            capability: .taskMetrics, module: "Observability",
            siteCount: 6, routing: .bypassesSeam,
            fallback: .none
        ),
        CapabilityUsage(
            capability: .urlCache, module: "ImageLoading",
            siteCount: 4, routing: .bypassesSeam,
            fallback: .documented("two-tier cache of our own, spec'd not built")
        ),
        CapabilityUsage(
            capability: .redirectPolicy, module: "Networking",
            siteCount: 1, routing: .bypassesSeam,
            fallback: .implemented("per-request override already on the seam")
        )
    ]

    public static func report(analyzer: PortabilityAnalyzer = .init()) -> PortabilityReport {
        analyzer.analyze(declaredSeams: declaredSeams, usages: usages)
    }
}
