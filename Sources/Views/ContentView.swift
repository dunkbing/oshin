import SwiftData
import SwiftUI

// MARK: - Detail Tab

enum DetailTab: String, CaseIterable {
    case chat
    case terminal
    case git

    var icon: String {
        switch self {
        case .chat: return "bubble.left"
        case .terminal: return "terminal"
        case .git: return "arrow.triangle.branch"
        }
    }
}

// MARK: - Tab Bar

struct DetailTabBar: View {
    @Binding var selectedTab: DetailTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 16))
                        .frame(width: 44, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == tab ? Color.primary.opacity(0.1) : Color.clear)
                        )
                        .foregroundStyle(selectedTab == tab ? .primary : .tertiary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Content View

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
            Group {
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
            .ignoresSafeArea(.container, edges: .top)
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
    @State private var selectedTab: DetailTab = .git
    @AppStorage("diffFontSize") private var diffFontSize: Double = 12

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            DetailTabBar(selectedTab: $selectedTab)

            Divider()

            // Tab content
            switch selectedTab {
            case .chat:
                ChatTabView()
            case .terminal:
                TerminalTabView()
            case .git:
                GitTabView(
                    repository: repository,
                    gitService: gitService,
                    selectedFile: $selectedFile,
                    diffFontSize: diffFontSize
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

// MARK: - Chat Tab (Placeholder)

struct ChatTabView: View {
    var body: some View {
        ContentUnavailableView(
            "Chat",
            systemImage: "bubble.left",
            description: Text("Agent chat interface coming soon.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Terminal Tab (Placeholder)

struct TerminalTabView: View {
    var body: some View {
        ContentUnavailableView(
            "Terminal",
            systemImage: "terminal",
            description: Text("Terminal integration coming soon.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Git Tab

struct GitTabView: View {
    let repository: Repository
    @ObservedObject var gitService: GitService
    @Binding var selectedFile: String?
    let diffFontSize: Double

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
