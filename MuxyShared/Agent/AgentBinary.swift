import Foundation

public enum AgentBinary {
    public static func resolvePath(command: String, env: [String: String]) -> URL? {
        guard let firstToken = firstToken(in: command) else { return nil }
        if firstToken.hasPrefix("/") {
            return URL(fileURLWithPath: firstToken)
        }
        let pathEntries = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for entry in pathEntries where !entry.isEmpty {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent(firstToken)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public static func stripBinaryName(from command: String, kind: AgentKind) -> String? {
        guard let expected = kind.expectedBinaryName,
              let firstToken = firstToken(in: command)
        else { return nil }
        let trailingName = (firstToken as NSString).lastPathComponent
        guard trailingName == expected else { return nil }
        let after = command.drop { !$0.isWhitespace }
        return String(after).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func firstToken(in command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("\"") {
            let body = trimmed.dropFirst()
            if let close = body.firstIndex(of: "\"") {
                return String(body[..<close])
            }
        }
        return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}
