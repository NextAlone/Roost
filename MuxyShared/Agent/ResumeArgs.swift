import Foundation

public enum ResumeArgs {
    public static func containsShellMetacharacters(_ s: String) -> Bool {
        let bad: [Character] = [";", "|", "&", "`", "\n", "\r", ">", "<"]
        if s.contains("$(") { return true }
        for ch in s where bad.contains(ch) {
            return true
        }
        return false
    }

    public static func captureLooksValid(_ captured: String, kind: AgentKind) -> Bool {
        guard let expected = kind.expectedBinaryName else { return false }
        let firstToken = AgentBinary.firstToken(in: captured) ?? ""
        let trailing = (firstToken as NSString).lastPathComponent
        guard trailing == expected else { return false }
        return !containsShellMetacharacters(captured)
    }
}
