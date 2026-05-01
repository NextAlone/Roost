import Foundation
import MuxyShared

enum AgentToolbarSettings {
    static let visibleAgentsKey = "muxy.agentToolbar.visibleAgents"

    static var configurableAgentKinds: [AgentKind] {
        AgentKind.allCases.filter { $0 != .terminal }
    }

    static var defaultVisibleAgentsRaw: String {
        encode(configurableAgentKinds)
    }

    static func visibleAgentKinds(from rawValue: String) -> [AgentKind] {
        let enabled = Set(rawValue.split(separator: ",").map(String.init))
        return configurableAgentKinds.filter { enabled.contains($0.rawValue) }
    }

    static func isVisible(_ kind: AgentKind, in rawValue: String) -> Bool {
        visibleAgentKinds(from: rawValue).contains(kind)
    }

    static func setVisible(_ visible: Bool, for kind: AgentKind, in rawValue: String) -> String {
        var kinds = visibleAgentKinds(from: rawValue)
        if visible {
            if !kinds.contains(kind) {
                kinds.append(kind)
            }
        } else {
            kinds.removeAll { $0 == kind }
        }
        let ordered = configurableAgentKinds.filter { kinds.contains($0) }
        return encode(ordered)
    }

    private static func encode(_ kinds: [AgentKind]) -> String {
        kinds.map(\.rawValue).joined(separator: ",")
    }
}
