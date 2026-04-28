import MuxyShared
import SwiftUI

enum CreateWorktreeResult {
    case created(Worktree, runSetup: Bool)
    case cancelled
}

struct CreateWorktreeSheet: View {
    let project: Project
    let onFinish: (CreateWorktreeResult) -> Void

    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var name: String = ""
    @State private var branchName: String = ""
    @State private var branchNameEdited = false
    @State private var createNewBranch = true
    @State private var selectedExistingBranch: String = ""
    @State private var availableBranches: [String] = []
    @State private var setupCommands: [String] = []
    @State private var runSetup = false
    @State private var inProgress = false
    @State private var errorMessage: String?

    private let gitRepository = GitRepositoryService()
    @Environment(\.vcsWorktreeControllerResolver) private var vcsResolver

    private var projectVcsKind: VcsKind {
        worktreeStore.primary(for: project.id)?.vcsKind ?? .git
    }

    private var refTerm: String {
        projectVcsKind == .jj ? "Bookmark" : "Branch"
    }

    private var refTermLower: String {
        projectVcsKind == .jj ? "bookmark" : "branch"
    }

    private var sampleSetupConfig: String {
        """
        {
          "schemaVersion": 1,
          "setup": [
            { "command": "pnpm install" },
            { "command": "pnpm dev" }
          ]
        }
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Workspace")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 11)).foregroundStyle(MuxyTheme.fgMuted)
                TextField("feature-x", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            SegmentedPicker(
                selection: $createNewBranch,
                options: [(true, "Create new \(refTermLower)"), (false, "Use existing \(refTermLower)")]
            )

            if createNewBranch {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(refTerm) Name").font(.system(size: 11)).foregroundStyle(MuxyTheme.fgMuted)
                    TextField("feature-x", text: $branchName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: branchName) { _, newValue in
                            branchNameEdited = newValue != name
                        }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(refTerm).font(.system(size: 11)).foregroundStyle(MuxyTheme.fgMuted)
                    Picker("", selection: $selectedExistingBranch) {
                        ForEach(availableBranches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .labelsHidden()
                }
            }

            if setupCommands.isEmpty {
                setupCommandsGuideSection
            } else {
                setupCommandsSection
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { onFinish(.cancelled) }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { Task { await create() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate || inProgress)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            await loadBranches()
            loadSetupCommands()
        }
        .onChange(of: name) { _, newValue in
            guard createNewBranch, !branchNameEdited else { return }
            branchName = newValue
        }
        .onChange(of: createNewBranch) { _, isCreatingNewBranch in
            guard isCreatingNewBranch, !branchNameEdited else { return }
            branchName = name
        }
    }

    private var setupCommandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
                Text("Setup commands from project config")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
            }
            Text("These commands will run in the new workspace's terminal. Only enable this if you trust this repository.")
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(setupCommands, id: \.self) { command in
                    Text(command)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MuxyTheme.fg)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 4))
            Toggle("Run these commands after creating the workspace", isOn: $runSetup)
                .font(.system(size: 11))
        }
        .padding(10)
        .background(MuxyTheme.hover, in: RoundedRectangle(cornerRadius: 6))
    }

    private var setupCommandsGuideSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
                Text("Optional setup commands")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
            }
            Text("To run setup commands after creating a workspace, add .roost/config.json in this repository.")
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(project.path)/.roost/config.json")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MuxyTheme.fg)
                .textSelection(.enabled)
            Text(sampleSetupConfig)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MuxyTheme.fg)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(10)
        .background(MuxyTheme.hover, in: RoundedRectangle(cornerRadius: 6))
    }

    private func loadSetupCommands() {
        guard let config = RoostConfigLoader.load(fromProjectPath: project.path) else {
            setupCommands = []
            return
        }
        setupCommands = WorktreeSetupRunner.setupCommands(config: config)
    }

    private var canCreate: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if createNewBranch {
            return !branchName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !selectedExistingBranch.isEmpty
    }

    private func loadBranches() async {
        do {
            let branches = try await gitRepository.listBranches(repoPath: project.path)
            await MainActor.run {
                availableBranches = branches
                if selectedExistingBranch.isEmpty {
                    selectedExistingBranch = branches.first ?? ""
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func create() async {
        inProgress = true
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let branch = createNewBranch
            ? branchName.trimmingCharacters(in: .whitespaces)
            : selectedExistingBranch

        let slug = Self.slug(from: trimmedName)
        let worktreeDirectory = WorkspaceLocationResolver
            .directory(projectID: project.id, projectPath: project.path, name: slug)
            .path(percentEncoded: false)

        if FileManager.default.fileExists(atPath: worktreeDirectory) {
            await MainActor.run {
                inProgress = false
                errorMessage = "A workspace with this name already exists on disk."
            }
            return
        }

        let kind = await MainActor.run { worktreeStore.primary(for: project.id)?.vcsKind ?? .git }
        let controller = vcsResolver.controller(kind)
        do {
            try await controller.addWorktree(
                repoPath: project.path,
                name: trimmedName,
                path: worktreeDirectory,
                ref: branch,
                createRef: createNewBranch
            )
        } catch {
            await MainActor.run {
                inProgress = false
                errorMessage = error.localizedDescription
            }
            return
        }

        let worktree = Worktree(
            name: trimmedName,
            path: worktreeDirectory,
            branch: branch,
            ownsBranch: createNewBranch,
            isPrimary: false,
            vcsKind: kind,
            jjWorkspaceName: kind == .jj ? trimmedName : nil
        )
        await MainActor.run {
            worktreeStore.add(worktree, to: project.id)
            inProgress = false
            onFinish(.created(worktree, runSetup: runSetup))
        }
    }

    private static func slug(from name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }
}
