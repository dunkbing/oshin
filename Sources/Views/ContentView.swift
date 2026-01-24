import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.order) private var workspaces: [Workspace]

    @State private var selectedWorkspace: Workspace?
    @State private var selectedRepository: Repository?

    var body: some View {
        NavigationSplitView {
            WorkspaceSidebarView(
                selectedWorkspace: $selectedWorkspace,
                selectedRepository: $selectedRepository
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            if let repository = selectedRepository {
                RepositoryDetailView(repository: repository)
            } else {
                ContentUnavailableView(
                    "No Repository Selected",
                    systemImage: "folder",
                    description: Text("Select a repository from the sidebar or add a new one.")
                )
            }
        }
        .onAppear {
            if selectedWorkspace == nil {
                selectedWorkspace = workspaces.first
            }
        }
        .onChange(of: workspaces) { _, newValue in
            if selectedWorkspace == nil {
                selectedWorkspace = newValue.first
            }
        }
    }
}

struct RepositoryDetailView: View {
    let repository: Repository
    @StateObject private var gitService = GitService()
    @State private var selectedFile: String?
    @AppStorage("diffFontSize") private var diffFontSize: Double = 12

    var body: some View {
        VStack(spacing: 0) {
            // Header with git status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 8) {
                        if !gitService.currentStatus.currentBranch.isEmpty {
                            Label(gitService.currentStatus.currentBranch, systemImage: "arrow.triangle.branch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(repository.path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Git status badge
                if gitService.currentStatus.hasChanges {
                    GitStatusView(
                        additions: gitService.currentStatus.additions,
                        deletions: gitService.currentStatus.deletions,
                        untrackedFiles: gitService.currentStatus.untrackedFiles.count
                    )
                }

                // Refresh button
                Button {
                    Task {
                        await gitService.reloadStatus()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(gitService.isLoading)
            }
            .padding()

            Divider()

            // Main content area with split view
            if gitService.isLoading {
                ProgressView("Loading git status...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if gitService.currentStatus.hasChanges {
                HSplitView {
                    // Left: File list and commit section
                    GitSidebarView(
                        gitStatus: gitService.currentStatus,
                        isOperationPending: gitService.isOperationPending,
                        selectedFile: selectedFile,
                        onStageFile: { file in
                            gitService.stageFile(file)
                        },
                        onUnstageFile: { file in
                            gitService.unstageFile(file)
                        },
                        onStageAll: { completion in
                            gitService.stageAll(completion: completion)
                        },
                        onUnstageAll: {
                            gitService.unstageAll()
                        },
                        onCommit: { message in
                            gitService.commit(message: message)
                        },
                        onFileClick: { file in
                            selectedFile = file
                            Task {
                                await gitService.loadFileDiff(for: file)
                            }
                        }
                    )
                    .frame(minWidth: 250, idealWidth: 280, maxWidth: 350)

                    // Right: Diff view
                    DiffView(
                        diffOutput: gitService.selectedFileDiff,
                        fileName: selectedFile ?? "",
                        fontSize: diffFontSize
                    )
                    .frame(minWidth: 400)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text("Working tree is clean.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            gitService.setRepositoryPath(repository.path)
        }
        .onChange(of: repository.path) { _, newPath in
            gitService.setRepositoryPath(newPath)
            selectedFile = nil
        }
    }
}

struct GitChangesListView: View {
    let status: GitStatus

    var body: some View {
        List {
            if !status.stagedFiles.isEmpty {
                Section("Staged Changes (\(status.stagedFiles.count))") {
                    ForEach(status.stagedFiles, id: \.self) { file in
                        FileChangeRow(file: file, type: .staged)
                    }
                }
            }

            if !status.modifiedFiles.isEmpty {
                Section("Modified (\(status.modifiedFiles.count))") {
                    ForEach(status.modifiedFiles, id: \.self) { file in
                        FileChangeRow(file: file, type: .modified)
                    }
                }
            }

            if !status.untrackedFiles.isEmpty {
                Section("Untracked (\(status.untrackedFiles.count))") {
                    ForEach(status.untrackedFiles, id: \.self) { file in
                        FileChangeRow(file: file, type: .untracked)
                    }
                }
            }

            if !status.conflictedFiles.isEmpty {
                Section("Conflicts (\(status.conflictedFiles.count))") {
                    ForEach(status.conflictedFiles, id: \.self) { file in
                        FileChangeRow(file: file, type: .conflicted)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct FileChangeRow: View {
    let file: String
    let type: FileChangeType

    enum FileChangeType {
        case staged, modified, untracked, conflicted

        var color: Color {
            switch self {
            case .staged: return .green
            case .modified: return .orange
            case .untracked: return .blue
            case .conflicted: return .red
            }
        }

        var icon: String {
            switch self {
            case .staged: return "checkmark.circle.fill"
            case .modified: return "pencil.circle.fill"
            case .untracked: return "plus.circle.fill"
            case .conflicted: return "exclamationmark.triangle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: type.icon)
                .foregroundStyle(type.color)
                .font(.system(size: 12))

            Text(file)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
