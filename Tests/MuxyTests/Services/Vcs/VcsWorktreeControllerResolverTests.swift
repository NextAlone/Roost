import Foundation
import SwiftUI
import Testing

@testable import Roost

@Suite("VcsWorktreeControllerResolver")
struct VcsWorktreeControllerResolverTests {
    @Test("default resolver delegates to factory")
    func defaultResolves() {
        let resolver = VcsWorktreeControllerResolver.default
        #expect(resolver.controller(.git) is GitWorktreeController)
        #expect(resolver.controller(.jj) is JjWorktreeController)
    }

    @Test("custom resolver returns injected controller")
    func customResolver() {
        let stub = ResolverStubController()
        let resolver = VcsWorktreeControllerResolver { _ in stub }
        #expect(resolver.controller(.git) as? ResolverStubController === stub)
        #expect(resolver.controller(.jj) as? ResolverStubController === stub)
    }

    @Test("EnvironmentValues default is the default resolver")
    @MainActor
    func environmentDefault() {
        let env = EnvironmentValues()
        let resolver = env.vcsWorktreeControllerResolver
        #expect(resolver.controller(.git) is GitWorktreeController)
    }
}

final class ResolverStubController: VcsWorktreeController, @unchecked Sendable {
    func addWorktree(repoPath: String, name: String, path: String, ref: String?, createRef: Bool) async throws {}
    func removeWorktree(repoPath: String, path: String, identifier: String?, force: Bool) async throws {}
    func deleteRef(repoPath: String, name: String) async throws {}
}
