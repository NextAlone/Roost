import Foundation
import MuxyShared
import Testing

@Suite("AgentBinary path resolution")
struct AgentBinaryResolvePathTests {
    @Test("absolute path returned directly")
    func absolutePathIsReturnedDirectly() {
        let path = AgentBinary.resolvePath(
            command: "/usr/local/bin/claude --foo",
            env: [:]
        )
        #expect(path?.path == "/usr/local/bin/claude")
    }

    @Test("uses PATH for bare name")
    func usesPATHForBareName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bin = dir.appendingPathComponent("xclaude")
        try Data().write(to: bin)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        let path = AgentBinary.resolvePath(
            command: "xclaude --foo",
            env: ["PATH": dir.path]
        )
        #expect(path?.path == bin.path)
    }

    @Test("quoted absolute path tokenized")
    func quotedAbsolutePathTokenized() {
        let path = AgentBinary.resolvePath(
            command: "\"/Applications/Claude.app/Contents/MacOS/claude\" --foo",
            env: [:]
        )
        #expect(path?.path == "/Applications/Claude.app/Contents/MacOS/claude")
    }

    @Test("unresolvable returns nil")
    func unresolvableReturnsNil() {
        let path = AgentBinary.resolvePath(
            command: "definitely-not-a-real-binary-xyz123 --foo",
            env: ["PATH": "/dev/null/empty"]
        )
        #expect(path == nil)
    }
}

@Suite("AgentBinary.stripBinaryName")
struct AgentBinaryStripTests {
    @Test("claude strips leading binary")
    func claudeStripsLeadingBinary() {
        let result = AgentBinary.stripBinaryName(
            from: "claude --resume abc-123",
            kind: .claudeCode
        )
        #expect(result == "--resume abc-123")
    }

    @Test("absolute path binary is stripped")
    func absolutePathBinaryIsStripped() {
        let result = AgentBinary.stripBinaryName(
            from: "/usr/local/bin/claude --resume abc",
            kind: .claudeCode
        )
        #expect(result == "--resume abc")
    }

    @Test("mismatched binary returns nil")
    func mismatchedBinaryReturnsNil() {
        let result = AgentBinary.stripBinaryName(
            from: "rogue --resume abc",
            kind: .claudeCode
        )
        #expect(result == nil)
    }

    @Test("empty command returns nil")
    func emptyCommandReturnsNil() {
        let result = AgentBinary.stripBinaryName(from: "", kind: .claudeCode)
        #expect(result == nil)
    }
}
