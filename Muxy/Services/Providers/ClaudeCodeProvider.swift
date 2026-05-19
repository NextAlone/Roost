import Foundation

struct ClaudeCodeProvider: AIProviderIntegration, AIUsageProvider {
    let id = "claude"
    let displayName = "Claude Code"
    let socketTypeKey = "claude_hook"
    let iconName = "claude"
    let executableNames = ["claude"]

    private static let credentialsKeychainService = "Claude Code-credentials"
    private static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")

    private static func credentialsFilePath(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let base = env["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "\(NSHomeDirectory())/.claude"
        return "\(base)/.credentials.json"
    }

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        await AIUsageSession.fetchSnapshot(
            provider: self,
            messages: AIUsageSessionMessages(
                missingCredentials: "Sign in to Claude",
                unauthenticated: "Sign in to Claude"
            ),
            buildRequest: {
                guard let endpoint = Self.usageEndpoint else { throw AIUsageAuthError.missingCredentials }
                let token = try readAccessToken()
                var request = URLRequest(url: endpoint)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
                return request
            },
            parse: ClaudeUsageParser.parseMetricRows(from:)
        )
    }

    private func readAccessToken() throws -> String {
        let env = ProcessInfo.processInfo.environment

        if let token = AIUsageTokenReader.fromEnvironment(keys: ["CLAUDE_CODE_OAUTH_TOKEN"], env: env) {
            return token
        }

        if let token = try AIUsageTokenReader.fromJSONFile(
            path: Self.credentialsFilePath(env: env),
            nestedKeyPath: ["claudeAiOauth"],
            valueKeys: ["accessToken"]
        ), !token.isEmpty {
            return token
        }

        let account = env["USER"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw = AIUsageTokenReader.fromKeychain(service: Self.credentialsKeychainService, account: account),
           let data = raw.data(using: .utf8),
           let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = payload["claudeAiOauth"] as? [String: Any],
           let token = AIUsageParserSupport.string(in: oauth, keys: ["accessToken"]),
           !token.isEmpty
        {
            return token
        }

        throw AIUsageAuthError.missingCredentials
    }
}
