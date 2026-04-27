import Foundation
import Testing
import MuxyShared

@testable import Roost

private let jjIntegrationGitAvailable: Bool = {
    let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git", "/bin/git"]
    return candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
}()

@Suite(
    "Jj live integration",
    .enabled(if: JjProcessRunner.resolveExecutable() != nil && jjIntegrationGitAvailable)
)
struct JjIntegrationTests {
    @Test("create temp jj repo, query root + version + status + op")
    func smoke() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("jj-smoke-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        guard let exec = JjProcessRunner.resolveExecutable() else {
            Issue.record("jj not found")
            return
        }
        let initResult = try await JjProcessRunner.runRaw(
            executable: exec,
            arguments: ["git", "init"],
            currentDirectory: tmp.path
        )
        #expect(initResult.status == 0, "jj git init failed: \(initResult.stderr)")

        let svc = JjRepositoryService()
        #expect(try await svc.isJjRepo(repoPath: tmp.path))

        let v = try await svc.version()
        #expect(v >= JjVersion.minimumSupported, "jj version \(v) below minimum")

        let opId = try await svc.currentOpId(repoPath: tmp.path)
        #expect(!opId.isEmpty)

        let statusResult = try await JjProcessRunner.run(
            repoPath: tmp.path,
            command: ["status"],
            snapshot: .ignore
        )
        let raw = String(data: statusResult.stdout, encoding: .utf8) ?? ""
        let status = try JjStatusParser.parse(raw)
        #expect(status.entries.isEmpty)
    }
}
