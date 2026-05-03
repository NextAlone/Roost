import Foundation

@objc
public protocol RoostHostdXPCProtocol {
    func runtimeOwnership(reply: @escaping @Sendable (Data) -> Void)
    func createSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func markExited(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func listLiveSessions(reply: @escaping @Sendable (Data) -> Void)
    func listAllSessions(reply: @escaping @Sendable (Data) -> Void)
    func deleteSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func pruneExited(reply: @escaping @Sendable (Data) -> Void)
    func markAllRunningExited(reply: @escaping @Sendable (Data) -> Void)
    func attachSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func releaseSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func terminateSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func readSessionOutput(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func writeSessionInput(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
    func resizeSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
}
