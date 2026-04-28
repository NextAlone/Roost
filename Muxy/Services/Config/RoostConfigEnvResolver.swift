import Foundation
import MuxyShared

enum RoostConfigEnvResolver {
    typealias KeychainReader = (String, String?) -> String?

    static func resolve(
        plain: [String: String],
        keychain: [String: RoostConfigKeychainEnv],
        keychainReader: KeychainReader = AIUsageTokenReader.fromKeychain
    ) -> [String: String] {
        var resolved = plain
        for (key, reference) in keychain where !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let value = keychainReader(reference.service, reference.account) else { continue }
            resolved[key] = value
        }
        return resolved
    }
}
