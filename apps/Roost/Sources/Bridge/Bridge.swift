import Foundation

/// Swift-facing facade over the generated swift-bridge bindings in
/// `Generated/RoostBridge.swift`. Wraps `RustString` returns in Swift-native
/// types so callers don't touch swift-bridge internals.
enum RoostBridge {
    static var version: String {
        roost_bridge_version().toString()
    }

    static func greet(_ name: String) -> String {
        roost_greet(name).toString()
    }

    static func prepareSession(agent: String) -> SessionSpecSwift {
        let raw = roost_prepare_session(agent)
        return SessionSpecSwift(
            command: raw.command.toString(),
            workingDirectory: raw.working_directory.toString(),
            agentKind: raw.agent_kind.toString()
        )
    }
}

/// Swift-native copy of `Generated.SessionSpec` so the rest of the app never
/// stores `RustString`s (which carry FFI ownership semantics).
struct SessionSpecSwift: Equatable {
    let command: String
    let workingDirectory: String
    let agentKind: String
}
