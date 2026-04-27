import Foundation
import Testing

@testable import Roost

@Suite("VcsWorktreeControllerFactory")
struct VcsWorktreeControllerFactoryTests {
    @Test("returns GitWorktreeController for .git")
    func git() {
        let controller = VcsWorktreeControllerFactory.controller(for: .git)
        #expect(controller is GitWorktreeController)
    }

    @Test("returns JjWorktreeController for .jj")
    func jj() {
        let controller = VcsWorktreeControllerFactory.controller(for: .jj)
        #expect(controller is JjWorktreeController)
    }
}
