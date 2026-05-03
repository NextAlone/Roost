public protocol HostdProcessKeepalive: Sendable {
    func retainSession()
    func releaseSession()
}

public struct NoopHostdProcessKeepalive: HostdProcessKeepalive {
    public init() {}

    public func retainSession() {}

    public func releaseSession() {}
}
