import Testing

@testable import Roost

@Suite("UserShellEnvironmentResolver")
struct UserShellEnvironmentResolverTests {
    @Test("uses login shell path when available")
    func loginShellPath() {
        let path = UserShellEnvironmentResolver.path(
            environment: ["PATH": "/usr/bin:/bin"],
            shell: "/run/current-system/sw/bin/fish",
            runShellPath: { shell, environment in
                #expect(shell == "/run/current-system/sw/bin/fish")
                #expect(environment["PATH"] == "/usr/bin:/bin")
                return "/Users/me/.local/bin:/etc/profiles/per-user/me/bin:/usr/bin:/bin"
            }
        )

        #expect(path == "/Users/me/.local/bin:/etc/profiles/per-user/me/bin:/usr/bin:/bin")
    }

    @Test("fallback path includes common user binary directories")
    func fallbackPath() {
        let path = UserShellEnvironmentResolver.path(
            environment: ["HOME": "/Users/me", "USER": "me", "PATH": "/usr/bin:/bin"],
            shell: "/missing/fish",
            runShellPath: { _, _ in nil }
        )

        #expect(path.contains("/Users/me/.local/bin"))
        #expect(path.contains("/etc/profiles/per-user/me/bin"))
        #expect(path.contains("/run/current-system/sw/bin"))
        #expect(path.contains("/usr/bin:/bin"))
    }
}
