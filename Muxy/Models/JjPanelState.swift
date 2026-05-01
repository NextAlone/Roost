import Foundation
import MuxyShared
import Observation

enum JjChangesRevsetPreset: String, CaseIterable, Identifiable {
    case `default`
    case currentStack
    case bookmarks
    case all
    case conflicts
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: "Default"
        case .currentStack: "Current Stack"
        case .bookmarks: "Bookmarks"
        case .all: "All"
        case .conflicts: "Conflicts"
        case .custom: "Custom"
        }
    }

    var shortTitle: String {
        switch self {
        case .default: "Default"
        case .currentStack: "Stack"
        case .bookmarks: "Marks"
        case .all: "All"
        case .conflicts: "Conflicts"
        case .custom: "Custom"
        }
    }

    var revset: String? {
        switch self {
        case .default: nil
        case .currentStack: "::@ & mutable()"
        case .bookmarks: "bookmarks()"
        case .all: "all()"
        case .conflicts: "conflicts()"
        case .custom: nil
        }
    }

    var canApply: Bool {
        self != .custom
    }

    static var menuPresets: [JjChangesRevsetPreset] {
        allCases.filter(\.canApply)
    }
}

enum JjChangeGraphFilter: String, CaseIterable, Identifiable {
    case ancestors
    case descendants
    case around
    case mutableStack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ancestors: "Show Ancestors"
        case .descendants: "Show Descendants"
        case .around: "Show Around This Change"
        case .mutableStack: "Show Mutable Stack to This"
        }
    }

    func revset(for targetRevset: String) -> String {
        switch self {
        case .ancestors: "::\(targetRevset)"
        case .descendants: "\(targetRevset)::"
        case .around: "::\(targetRevset) | \(targetRevset)::"
        case .mutableStack: "reachable(\(targetRevset), mutable())"
        }
    }
}

@MainActor
@Observable
final class JjPanelState {
    let repoPath: String
    private(set) var snapshot: JjPanelSnapshot?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var activeChangesRevset: String = ""
    private(set) var changesRevsetPreset: JjChangesRevsetPreset = .default

    private let loader: JjPanelLoader

    init(repoPath: String, loader: JjPanelLoader = JjPanelLoader()) {
        self.repoPath = repoPath
        self.loader = loader
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await loader.load(repoPath: repoPath, changesRevset: normalizedChangesRevset)
            snapshot = result
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func applyChangesRevset(_ revset: String) async {
        activeChangesRevset = revset.trimmingCharacters(in: .whitespacesAndNewlines)
        changesRevsetPreset = activeChangesRevset.isEmpty ? .default : .custom
        await refresh()
    }

    func applyChangesRevsetPreset(_ preset: JjChangesRevsetPreset) async {
        guard preset.canApply else { return }
        activeChangesRevset = preset.revset ?? ""
        changesRevsetPreset = preset
        await refresh()
    }

    func applyChangeGraphFilter(_ filter: JjChangeGraphFilter, targetRevset: String) async {
        let trimmedTarget = targetRevset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else { return }
        activeChangesRevset = filter.revset(for: trimmedTarget)
        changesRevsetPreset = .custom
        await refresh()
    }

    func resetChangesRevset() async {
        activeChangesRevset = ""
        changesRevsetPreset = .default
        await refresh()
    }

    private var normalizedChangesRevset: String? {
        activeChangesRevset.isEmpty ? nil : activeChangesRevset
    }
}
