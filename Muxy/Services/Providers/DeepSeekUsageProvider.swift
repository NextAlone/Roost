import Foundation

struct DeepSeekUsageProvider: AIUsageProvider {
    let id = "deepseek"
    let displayName = "DeepSeek"
    let iconName = "deepseek"

    private static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        do {
            guard let balanceURL = Self.balanceURL else {
                return snapshot(state: .error(message: "Unable to fetch usage"))
            }
            let apiKey = try Self.readToken()
            let headers = [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json",
            ]

            let balance = try await Self.fetch(url: balanceURL, headers: headers)

            if balance.statusCode == 401 || balance.statusCode == 403 {
                return snapshot(state: .unavailable(message: "Invalid DeepSeek API key"))
            }
            guard (200 ..< 300).contains(balance.statusCode) else {
                usageLogger.error("DeepSeek usage request failed with status \(balance.statusCode)")
                return snapshot(state: .error(message: "Usage request failed"))
            }

            let rows = try DeepSeekUsageParser.parseMetricRows(from: balance.data)
            guard !rows.isEmpty else {
                return snapshot(state: .unavailable(message: "No usage data"))
            }

            return AIProviderUsageSnapshot(
                providerID: id,
                providerName: displayName,
                providerIconName: iconName,
                state: .available,
                rows: rows
            )
        } catch AIUsageAuthError.missingCredentials {
            return snapshot(state: .unavailable(message: "Set DEEPSEEK_API_KEY"))
        } catch {
            usageLogger.error("DeepSeek usage request failed: \(error.localizedDescription)")
            return snapshot(state: .error(message: "Unable to fetch usage"))
        }
    }

    private static func isDeepSeekBaseURL(_ url: String?) -> Bool {
        guard let url else { return false }
        return url.contains("deepseek.com")
    }

    static func readToken(
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileExists: ((String) -> Bool)? = nil,
        dataReader: ((String) throws -> Data)? = nil
    ) throws -> String {
        if let token = AIUsageTokenReader.fromEnvironment(keys: ["DEEPSEEK_API_KEY"], env: env) {
            return token
        }

        if isDeepSeekBaseURL(env["ANTHROPIC_BASE_URL"]),
           let token = AIUsageTokenReader.fromEnvironment(keys: ["ANTHROPIC_AUTH_TOKEN"], env: env)
        {
            return token
        }

        let doesFileExist = fileExists ?? { FileManager.default.fileExists(atPath: $0) }
        let readData = dataReader ?? { try Data(contentsOf: URL(fileURLWithPath: $0)) }

        let settingsPath = homeDirectory + "/.claude/settings.json"
        if doesFileExist(settingsPath) {
            let data = try readData(settingsPath)
            if let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let settingsEnv = payload["env"] as? [String: String],
               isDeepSeekBaseURL(settingsEnv["ANTHROPIC_BASE_URL"]),
               let token = settingsEnv["ANTHROPIC_AUTH_TOKEN"],
               !token.isEmpty
            {
                return token
            }
        }

        throw AIUsageAuthError.missingCredentials
    }

    private static func fetch(url: URL, headers: [String: String]) async throws -> (statusCode: Int, data: Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (http.statusCode, data)
    }
}
