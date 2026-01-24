import SwiftData
import SwiftUI

// MARK: - Detail Tab

enum DetailTab: String, CaseIterable {
    case chat
    case terminal
    case git

    var icon: String {
        switch self {
        case .chat: return "bubble.left.fill"
        case .terminal: return "terminal.fill"
        case .git: return "arrow.triangle.branch"
        }
    }

    var label: String {
        switch self {
        case .chat: return "Chat"
        case .terminal: return "Terminal"
        case .git: return "Git"
        }
    }
}

// MARK: - Tab Bar

struct DetailTabBar: View {
    @Binding var selectedTab: DetailTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11))
                        Text(tab.label)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.primary.opacity(0.12) : Color.clear)
                    )
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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

// MARK: - Repository Detail View

struct RepositoryDetailView: View {
    let repository: Repository
    @StateObject private var gitService = GitService()
    @State private var selectedFile: String?
    @State private var selectedTab: DetailTab = .git
    @AppStorage("diffFontSize") private var diffFontSize: Double = 12

    var body: some View {
        VStack(spacing: 0) {
            DetailTabBar(selectedTab: $selectedTab)
            Divider()

            // Tab content
            switch selectedTab {
            case .chat:
                ChatTabView(repositoryPath: repository.path)
            case .terminal:
                TerminalTabView()
            case .git:
                GitTabView(
                    repository: repository,
                    selectedFile: $selectedFile,
                    diffFontSize: diffFontSize
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(gitService)
        .onAppear {
            gitService.setRepositoryPath(repository.path)
        }
        .onChange(of: repository.path) { _, newPath in
            gitService.setRepositoryPath(newPath)
            selectedFile = nil
        }
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
    @EnvironmentObject private var gitService: GitService

    let repository: Repository
    @Binding var selectedFile: String?
    let diffFontSize: Double

    private var gitStatus: GitStatus { gitService.currentStatus }

    var body: some View {
        VStack(spacing: 0) {
            GitTabHeader(repository: repository)

            Divider()

            if gitService.isLoading {
                ProgressView("Loading git status...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if gitStatus.hasChanges {
                HSplitView {
                    GitSidebarView(
                        selectedFile: selectedFile,
                        onFileClick: { file in
                            selectedFile = file
                            Task {
                                await gitService.loadFileDiff(for: file)
                            }
                        }
                    )
                    .frame(minWidth: 250, idealWidth: 280, maxWidth: 350)

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Git Tab Header

struct GitTabHeader: View {
    @EnvironmentObject private var gitService: GitService

    let repository: Repository

    private var gitStatus: GitStatus { gitService.currentStatus }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(repository.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    if !gitStatus.currentBranch.isEmpty {
                        Label(gitStatus.currentBranch, systemImage: "arrow.triangle.branch")
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

            if gitStatus.hasChanges {
                GitStatusView(
                    additions: gitStatus.additions,
                    deletions: gitStatus.deletions,
                    untrackedFiles: gitStatus.untrackedFiles.count
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
    }
}
