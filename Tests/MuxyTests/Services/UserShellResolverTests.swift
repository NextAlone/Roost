import Testing

@testable import Roost

@Suite("UserShellResolver")
struct UserShellResolverTests {
    @Test("prefers account login shell over inherited SHELL")
    func prefersAccountLoginShell() {
        let shell = UserShellResolver.shell(
            environment: ["SHELL": "/bin/zsh"],
            accountShell: { "/run/current-system/sw/bin/fish" }
        )

        #expect(shell == "/run/current-system/sw/bin/fish")
    }

    @Test("falls back to inherited SHELL")
    func inheritedShellFallback() {
        let shell = UserShellResolver.shell(
            environment: ["SHELL": "/bin/zsh"],
            accountShell: { nil }
        )

        #expect(shell == "/bin/zsh")
    }

    @Test("falls back to zsh")
    func zshFallback() {
        let shell = UserShellResolver.shell(
            environment: [:],
            accountShell: { nil }
        )

        #expect(shell == "/bin/zsh")
    }
}
