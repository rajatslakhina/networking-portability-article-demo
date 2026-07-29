import Foundation

/// One thing an app relies on its networking stack to do.
///
/// The unit that matters is *not* "we call URLSession in 12 files". It is
/// "we depend on 14 distinct behaviours, and 9 of them are not HTTP".
public struct TransportCapability: Hashable, Sendable, Codable, Identifiable {

    /// Stable slug. Used for identity, dedupe, and Codable round-tripping, so it
    /// must not change once a capability is published.
    public let id: String
    public let name: String
    public let portability: PortabilityClass

    /// Why this capability sits in that class. Written to be read out loud in a
    /// design review, because that is where this argument actually gets had.
    public let rationale: String

    public init(id: String, name: String, portability: PortabilityClass, rationale: String) {
        self.id = id
        self.name = name
        self.portability = portability
        self.rationale = rationale
    }
}

// MARK: - The catalog

public extension TransportCapability {

    // --- Currency types: the workgroup is standardising exactly these ---

    static let requestResponseValues = TransportCapability(
        id: "request-response-values",
        name: "Request / response values",
        portability: .currencyType,
        rationale: "Method, path, headers, status, body. swift-http-types already models these as shared currency."
    )

    static let urlAndQueryEncoding = TransportCapability(
        id: "url-query-encoding",
        name: "URL & query encoding",
        portability: .currencyType,
        rationale: "Percent-encoding and component assembly are specified behaviour, not vendor behaviour."
    )

    static let jsonCoding = TransportCapability(
        id: "json-coding",
        name: "JSON encode / decode",
        portability: .currencyType,
        rationale: "Codable never knew which transport delivered the bytes. It does not care now."
    )

    // --- Protocol layer: reproducible, but somebody has to reproduce it ---

    static let tlsTrustEvaluation = TransportCapability(
        id: "tls-trust-evaluation",
        name: "TLS trust evaluation",
        portability: .protocolLayer,
        rationale: "A second stack can do TLS. Matching your pinning and trust-override behaviour exactly is the work."
    )

    static let http2Multiplexing = TransportCapability(
        id: "http2-multiplexing",
        name: "HTTP/2 multiplexing",
        portability: .protocolLayer,
        rationale: "Shared protocol implementations are a stated workgroup goal, so this improves for everyone."
    )

    static let webSocketFraming = TransportCapability(
        id: "websocket-framing",
        name: "WebSocket framing",
        portability: .protocolLayer,
        rationale: "Framing and ping/pong are specified. Your reconnect policy on top of them is yours to port."
    )

    static let redirectPolicy = TransportCapability(
        id: "redirect-policy",
        name: "Redirect policy",
        portability: .protocolLayer,
        rationale: "Redirect chasing is protocol behaviour, but your per-request override lives in a delegate callback."
    )

    // --- Platform services: not HTTP, and therefore not portable ---

    static let sharedCookieStorage = TransportCapability(
        id: "shared-cookie-storage",
        name: "Shared cookie storage",
        portability: .platformService,
        rationale: "HTTPCookieStorage is a process-wide jar your WKWebView reads too. A new client cannot join it."
    )

    static let systemCredentialStore = TransportCapability(
        id: "system-credential-store",
        name: "System credential store",
        portability: .platformService,
        rationale: "Auth challenges resolved against URLCredentialStorage and the Keychain, not against the wire."
    )

    static let backgroundTransfer = TransportCapability(
        id: "background-transfer",
        name: "Background transfer",
        portability: .platformService,
        rationale: "Out-of-process daemon that keeps transferring after your app is terminated. Nothing to reimplement."
    )

    static let waitsForConnectivity = TransportCapability(
        id: "waits-for-connectivity",
        name: "Waits for connectivity",
        portability: .platformService,
        rationale: "The system decides when the path is viable and wakes the task. That decision is not yours to make."
    )

    static let cellularPolicy = TransportCapability(
        id: "cellular-policy",
        name: "Cellular & constrained-path policy",
        portability: .platformService,
        rationale: "allowsCellularAccess and Low Data Mode are enforced by the OS path monitor, above any protocol."
    )

    static let systemProxyConfiguration = TransportCapability(
        id: "system-proxy-config",
        name: "System proxy configuration",
        portability: .platformService,
        rationale: "MDM-pushed proxy and PAC evaluation arrive from device configuration, not from your code."
    )

    static let taskMetrics = TransportCapability(
        id: "task-metrics",
        name: "Per-task transfer metrics",
        portability: .platformService,
        rationale: "URLSessionTaskMetrics is instrumentation the OS collects. Your dashboards quietly depend on it."
    )

    static let urlCache = TransportCapability(
        id: "url-cache",
        name: "Response caching",
        portability: .platformService,
        rationale: "URLCache is a shared on-disk store with its own eviction policy, not an HTTP feature you re-enable."
    )

    /// Every capability the demo knows about, ordered currency -> protocol -> platform.
    static let catalog: [TransportCapability] = [
        .requestResponseValues,
        .urlAndQueryEncoding,
        .jsonCoding,
        .tlsTrustEvaluation,
        .http2Multiplexing,
        .webSocketFraming,
        .redirectPolicy,
        .sharedCookieStorage,
        .systemCredentialStore,
        .backgroundTransfer,
        .waitsForConnectivity,
        .cellularPolicy,
        .systemProxyConfiguration,
        .taskMetrics,
        .urlCache
    ]

    /// Catalog lookup by slug. Returns nil rather than trapping so decoding a
    /// report written by a newer version of the catalog degrades instead of crashing.
    static func catalogEntry(id: String) -> TransportCapability? {
        catalog.first { $0.id == id }
    }
}
