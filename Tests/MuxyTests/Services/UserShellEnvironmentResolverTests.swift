import Foundation
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

    @Test("cached path reuses the resolved login shell path")
    func cachedPath() {
        var calls = 0
        let uniquePath = "/usr/bin:/bin:/tmp/roost-\(UUID().uuidString)"

        let first = UserShellEnvironmentResolver.cachedPath(
            environment: ["HOME": "/Users/me", "USER": "me", "PATH": uniquePath],
            shell: "/run/current-system/sw/bin/fish",
            runShellPath: { _, _ in
                calls += 1
                return "/Users/me/.local/bin:/usr/bin:/bin"
            }
        )
        let second = UserShellEnvironmentResolver.cachedPath(
            environment: ["HOME": "/Users/me", "USER": "me", "PATH": uniquePath],
            shell: "/run/current-system/sw/bin/fish",
            runShellPath: { _, _ in
                calls += 1
                return "/different"
            }
        )

        #expect(first == "/Users/me/.local/bin:/usr/bin:/bin")
        #expect(second == first)
        #expect(calls == 1)
    }
}
