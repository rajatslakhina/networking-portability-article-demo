import Foundation

/// Where a networking capability sits in the layered stack the Swift Networking
/// workgroup described when it was announced in June 2026: shared I/O primitives
/// at the bottom, common protocol implementations in the middle, and ergonomic
/// client APIs at the top.
///
/// The layer a capability belongs to is what actually decides whether it ports —
/// not whether your app happens to call it through a protocol you wrote.
public enum PortabilityClass: String, Sendable, Codable, CaseIterable {

    /// Shapes of data that libraries agree on: URLs, headers, status codes,
    /// request/response values, IP addresses, ports. The workgroup is explicitly
    /// defining these as *currency types* so libraries interoperate without
    /// coupling to one implementation. These move for free.
    case currencyType

    /// Wire behaviour: TLS, HTTP/1.1, HTTP/2, HTTP/3, QUIC, WebSocket framing,
    /// redirect handling. A second implementation can reproduce these — that is
    /// the entire point of sharing protocol implementations across the ecosystem —
    /// but reproducing them is real work with real risk.
    case protocolLayer

    /// Behaviour that is not a protocol at all: it is an operating-system service
    /// that URLSession happens to sit in front of. A shared cookie jar, the system
    /// credential store, the out-of-process background transfer daemon, system
    /// proxy configuration. No new HTTP client can hand these to you, because they
    /// were never HTTP in the first place.
    case platformService

    /// Relative effort multiplier applied per capability. The 1 / 4 / 16 spread is
    /// deliberately coarse: it encodes an ordering claim (platform services cost
    /// roughly an order of magnitude more than currency types), not a precise
    /// estimate. Recalibrate it against your own migration and the ordering holds.
    public var migrationWeight: Double {
        switch self {
        case .currencyType: return 1
        case .protocolLayer: return 4
        case .platformService: return 16
        }
    }

    public var displayName: String {
        switch self {
        case .currencyType: return "Currency type"
        case .protocolLayer: return "Protocol layer"
        case .platformService: return "Platform service"
        }
    }

    /// One-line justification, surfaced in the demo UI and in the printed report.
    public var explanation: String {
        switch self {
        case .currencyType:
            return "A shape of data. Any stack can produce it. Ports for free."
        case .protocolLayer:
            return "Wire behaviour. A second implementation can reproduce it — at a cost."
        case .platformService:
            return "An OS service, not a protocol. Nothing on the wire to reimplement."
        }
    }
}
