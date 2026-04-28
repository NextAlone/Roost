import MuxyShared
import Testing

@testable import Roost

@Suite("RoostConfigEnvResolver")
struct RoostConfigEnvResolverTests {
    @Test("resolves keychain values over plain values")
    func resolvesKeychainValues() {
        let env = RoostConfigEnvResolver.resolve(
            plain: ["TOKEN": "plain", "OTHER": "value"],
            keychain: ["TOKEN": RoostConfigKeychainEnv(service: "token-service", account: "work")],
            keychainReader: { service, account in
                service == "token-service" && account == "work" ? "secret" : nil
            }
        )

        #expect(env == ["TOKEN": "secret", "OTHER": "value"])
    }

    @Test("missing keychain values are skipped")
    func skipsMissingKeychainValues() {
        let env = RoostConfigEnvResolver.resolve(
            plain: ["OTHER": "value"],
            keychain: ["TOKEN": RoostConfigKeychainEnv(service: "missing")],
            keychainReader: { _, _ in nil }
        )

        #expect(env == ["OTHER": "value"])
    }
}
