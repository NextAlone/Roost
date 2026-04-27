import Foundation
import SwiftUI
import Testing

@testable import Roost

@Suite("VcsStatusProbe")
struct VcsStatusProbeTests {
    @Test("factory returns GitStatusProbe for .git")
    func factoryGit() {
        let probe = VcsStatusProbeFactory.probe(for: .git)
        #expect(probe is GitStatusProbe)
    }

    @Test("factory returns JjStatusProbe for .jj")
    func factoryJj() {
        let probe = VcsStatusProbeFactory.probe(for: .jj)
        #expect(probe is JjStatusProbe)
    }

    @Test("default resolver delegates to factory")
    func defaultResolves() {
        let resolver = VcsStatusProbeResolver.default
        #expect(resolver.probe(.git) is GitStatusProbe)
        #expect(resolver.probe(.jj) is JjStatusProbe)
    }

    @Test("custom resolver returns injected probe")
    func customResolver() {
        let stub = StatusProbeStub(answer: true)
        let resolver = VcsStatusProbeResolver { _ in stub }
        let probe = resolver.probe(.git)
        #expect(probe is StatusProbeStub)
    }

    @Test("JjStatusProbe with stubbed closure returns the stub answer")
    func jjStubbed() async {
        let probe = JjStatusProbe(probe: { _ in true })
        let result = await probe.hasUncommittedChanges(at: "/repo")
        #expect(result == true)
    }

    @Test("EnvironmentValues default is the default resolver")
    @MainActor
    func environmentDefault() {
        let env = EnvironmentValues()
        let resolver = env.vcsStatusProbeResolver
        #expect(resolver.probe(.git) is GitStatusProbe)
    }
}

final class StatusProbeStub: VcsStatusProbe, @unchecked Sendable {
    let answer: Bool
    init(answer: Bool) { self.answer = answer }
    func hasUncommittedChanges(at worktreePath: String) async -> Bool { answer }
}
