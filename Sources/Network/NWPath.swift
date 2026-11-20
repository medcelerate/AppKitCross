/// The route a connection uses. This port reports the status and the two endpoints of an
/// established connection; interface and link details are not modelled.
public struct NWPath: Equatable, CustomDebugStringConvertible, Sendable {
    /// Whether a path can be used by connections.
    public enum Status: Sendable {
        case satisfied
        case unsatisfied
        case requiresConnection
    }

    public let status: NWPath.Status
    public let localEndpoint: NWEndpoint?
    public let remoteEndpoint: NWEndpoint?

    init(status: Status, localEndpoint: NWEndpoint?, remoteEndpoint: NWEndpoint?) {
        self.status = status
        self.localEndpoint = localEndpoint
        self.remoteEndpoint = remoteEndpoint
    }

    public var debugDescription: String {
        var text = "\(status)"
        if let localEndpoint { text += ", local: \(localEndpoint.debugDescription)" }
        if let remoteEndpoint { text += ", remote: \(remoteEndpoint.debugDescription)" }
        return text
    }

    public static func == (lhs: NWPath, rhs: NWPath) -> Bool {
        lhs.status == rhs.status && lhs.localEndpoint == rhs.localEndpoint && lhs.remoteEndpoint == rhs.remoteEndpoint
    }
}
