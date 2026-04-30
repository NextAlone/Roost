import AppKit

enum WorkspaceRemovalConfirmation {
    static let defaultDeletesWorkspaceDirectory = false

    static func informativeText(hasUncommittedChanges: Bool) -> String {
        if hasUncommittedChanges {
            return [
                "Roost will remove this workspace from the sidebar.",
                "This workspace has uncommitted changes.",
                "Leave the checkbox off to keep the directory on disk.",
                "Check it to run teardown and delete the workspace directory from disk.",
            ].joined(separator: " ")
        }
        return [
            "Roost will remove this workspace from the sidebar.",
            "Leave the checkbox off to keep the directory on disk.",
            "Check it to run teardown and delete the workspace directory from disk.",
        ].joined(separator: " ")
    }

    @MainActor
    static func present(
        worktree: Worktree,
        hasUncommittedChanges: Bool,
        onConfirm: @escaping @MainActor (Bool) -> Void
    ) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let checkbox = NSButton(
            checkboxWithTitle: "Also delete workspace directory from disk",
            target: nil,
            action: nil
        )
        checkbox.state = defaultDeletesWorkspaceDirectory ? .on : .off

        let alert = NSAlert()
        alert.messageText = "Remove workspace \"\(worktree.name)\"?"
        alert.informativeText = informativeText(hasUncommittedChanges: hasUncommittedChanges)
        alert.alertStyle = hasUncommittedChanges ? .warning : .informational
        alert.icon = NSApp.applicationIconImage
        alert.accessoryView = checkbox
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            onConfirm(checkbox.state == .on)
        }
    }
}
