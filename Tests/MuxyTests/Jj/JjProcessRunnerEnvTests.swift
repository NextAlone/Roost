import Foundation
import Testing

@testable import Roost

@Suite("JjProcessRunner env + args")
struct JjProcessRunnerEnvTests {
    @Test("buildEnvironment strips JJ_* and sets locale")
    func envStripsAndSets() {
        let inherited = [
            "PATH": "/usr/local/bin:/usr/bin",
            "HOME": "/Users/test",
            "JJ_USER": "evil",
            "JJ_EMAIL": "evil@example.com",
            "JJ_CONFIG": "/keep/this",
            "LANG": "fr_FR.UTF-8",
            "TERM": "xterm-256color",
        ]
        let env = JjProcessRunner.buildEnvironment(inherited: inherited)
        #expect(env["LANG"] == "C.UTF-8")
        #expect(env["LC_ALL"] == "C.UTF-8")
        #expect(env["NO_COLOR"] == "1")
        #expect(env["JJ_USER"] == nil)
        #expect(env["JJ_EMAIL"] == nil)
        #expect(env["JJ_CONFIG"] == "/keep/this")
        #expect(env["HOME"] == "/Users/test")
        #expect(env["PATH"]?.contains("/usr/local/bin") == true)
    }

    @Test("buildArguments injects --no-pager --color=never for read commands")
    func argsInjectGlobals() {
        let args = JjProcessRunner.buildArguments(
            repoPath: "/repo",
            command: ["status"],
            snapshot: .ignore,
            atOp: nil
        )
        #expect(args.first == "--repository")
        #expect(args.contains("/repo"))
        #expect(args.contains("--no-pager"))
        #expect(args.contains("--color=never"))
        #expect(args.contains("--ignore-working-copy"))
        #expect(args.last == "status")
    }

    @Test("buildArguments injects --at-op when provided")
    func argsAtOp() {
        let args = JjProcessRunner.buildArguments(
            repoPath: "/repo",
            command: ["log", "-r", "@"],
            snapshot: .ignore,
            atOp: "abc123"
        )
        #expect(args.contains("--at-op"))
        #expect(args.contains("abc123"))
    }

    @Test("buildArguments omits --ignore-working-copy when snapshot is allowed")
    func argsAllowSnapshot() {
        let args = JjProcessRunner.buildArguments(
            repoPath: "/repo",
            command: ["new"],
            snapshot: .allow,
            atOp: nil
        )
        #expect(!args.contains("--ignore-working-copy"))
    }
}
