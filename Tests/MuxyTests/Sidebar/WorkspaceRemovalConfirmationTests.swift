import Testing

@testable import Roost

@Suite("WorkspaceRemovalConfirmation")
struct WorkspaceRemovalConfirmationTests {
    @Test("default choice keeps workspace directory")
    func defaultChoiceKeepsWorkspaceDirectory() {
        #expect(WorkspaceRemovalConfirmation.defaultDeletesWorkspaceDirectory == false)
    }

    @Test("uncommitted changes text explains cleanup risk")
    func uncommittedChangesTextExplainsCleanupRisk() {
        let text = WorkspaceRemovalConfirmation.informativeText(hasUncommittedChanges: true)

        #expect(text.contains("uncommitted changes"))
        #expect(text.contains("Leave the checkbox off"))
        #expect(text.contains("delete the workspace directory"))
    }
}
