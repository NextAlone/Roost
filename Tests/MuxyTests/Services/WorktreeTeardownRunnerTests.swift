import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("WorktreeTeardownRunner")
struct WorktreeTeardownRunnerTests {
    @Test("filters blank teardown commands")
    func blankCommands() {
        let config = RoostConfig(teardown: [
            RoostConfigSetupCommand(command: "  "),
            RoostConfigSetupCommand(command: "make clean")
        ])

        #expect(WorktreeTeardownRunner.teardownCommands(config: config) == ["make clean"])
    }

    @Test("relative cwd resolves against worktree path")
    func relativeWorkingDirectory() {
        let command = RoostConfigSetupCommand(command: "make clean", cwd: "tools")
        let url = WorktreeTeardownRunner.resolvedWorkingDirectory(
            command: command,
            worktreePath: "/tmp/worktree"
        )

        #expect(url.path == "/tmp/worktree/tools")
    }

    @Test("absolute cwd is used directly")
    func absoluteWorkingDirectory() {
        let command = RoostConfigSetupCommand(command: "make clean", cwd: "/tmp/tools")
        let url = WorktreeTeardownRunner.resolvedWorkingDirectory(
            command: command,
            worktreePath: "/tmp/worktree"
        )

        #expect(url.path == "/tmp/tools")
    }

    @Test("global and command env resolve over inherited env")
    func resolvedEnvironment() {
        let config = RoostConfig(
            env: ["GLOBAL": "plain", "OVERRIDE": "global"],
            keychainEnv: ["GLOBAL_SECRET": RoostConfigKeychainEnv(service: "global-token")]
        )
        let command = RoostConfigSetupCommand(
            command: "make clean",
            env: ["OVERRIDE": "local"],
            keychainEnv: ["LOCAL_SECRET": RoostConfigKeychainEnv(service: "local-token", account: "work")]
        )

        let env = WorktreeTeardownRunner.resolvedEnvironment(
            command: command,
            globalConfig: config,
            inherited: ["GLOBAL": "inherited", "PATH": "/bin"],
            keychainReader: { service, account in
                [
                    "global-token:": "global secret",
                    "local-token:work": "local secret"
                ]["\(service):\(account ?? "")"]
            }
        )

        #expect(env == [
            "GLOBAL": "plain",
            "GLOBAL_SECRET": "global secret",
            "LOCAL_SECRET": "local secret",
            "OVERRIDE": "local",
            "PATH": "/bin"
        ])
    }
}
