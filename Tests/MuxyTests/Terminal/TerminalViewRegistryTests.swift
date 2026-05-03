import Foundation
import Testing

@testable import Roost

@MainActor
@Suite("TerminalViewRegistry")
struct TerminalViewRegistryTests {
    @Test("view creation replaces stale instances")
    func viewCreationReplacesStaleInstances() {
        let paneID = UUID()
        let first = TerminalViewRegistry.shared.view(
            for: paneID,
            workingDirectory: "/tmp",
            command: "printf first"
        )
        let second = TerminalViewRegistry.shared.view(
            for: paneID,
            workingDirectory: "/tmp",
            command: "printf second"
        )
        defer {
            TerminalViewRegistry.shared.removeView(for: paneID)
        }

        #expect(first !== second)
        #expect(TerminalViewRegistry.shared.existingView(for: paneID) === second)
    }
}
