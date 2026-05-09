import Foundation

public enum AgentReloadCommandBuilder {
    public static func build(
        preset: AgentPreset,
        captured: String?
    ) -> String {
        let base = preset.defaultCommand ?? ""
        guard let captured else { return base }
        switch preset.kind.resumeStrategy {
        case .notSupported:
            return base
        case .replaceWithCaptured:
            guard ResumeArgs.captureLooksValid(captured, kind: preset.kind) else {
                return base
            }
            return captured
        case .appendArgs:
            guard let args = AgentBinary.stripBinaryName(from: captured, kind: preset.kind),
                  !ResumeArgs.containsShellMetacharacters(args)
            else { return base }
            return "\(base) \(args)"
        }
    }
}
