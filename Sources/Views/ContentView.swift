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
    @StateObject private var ghosttyApp = Ghostty.App()
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
                TerminalTabView(workingDirectory: repository.path, ghosttyApp: ghosttyApp)
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

// MARK: - Terminal Tab

struct TerminalTabView: View {
    let workingDirectory: String
    @ObservedObject var ghosttyApp: Ghostty.App

    private let sessionManager = TerminalSessionManager.shared

    @State private var shouldFocus: Bool = false
    @State private var focusVersion: Int = 0
    @State private var terminalTitle: String = "Terminal"
    @State private var processExited: Bool = false
    @State private var isResizing: Bool = false
    @State private var terminalSize: (columns: UInt16, rows: UInt16) = (0, 0)
    @State private var hideWorkItem: DispatchWorkItem?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TerminalViewWrapper(
                    workingDirectory: workingDirectory,
                    ghosttyApp: ghosttyApp,
                    sessionManager: sessionManager,
                    onProcessExit: {
                        processExited = true
                    },
                    onTitleChange: { title in
                        terminalTitle = title
                    },
                    shouldFocus: shouldFocus,
                    isFocused: true,
                    focusVersion: focusVersion,
                    size: geo.size
                )

                // Resize overlay
                if isResizing {
                    ResizeOverlay(columns: terminalSize.columns, rows: terminalSize.rows)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.1), value: isResizing)
                }

                // Process exited overlay
                if processExited {
                    VStack(spacing: 16) {
                        Image(systemName: "terminal")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("Terminal session ended")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Button("Restart Terminal") {
                            restartTerminal()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
            .onChange(of: geo.size) { _, _ in
                handleSizeChange()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Focus terminal on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                shouldFocus = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    shouldFocus = false
                }
            }
        }
        .onDisappear {
            hideWorkItem?.cancel()
            hideWorkItem = nil
        }
    }

    private func handleSizeChange() {
        guard let terminal = sessionManager.getTerminal(for: workingDirectory),
              let termSize = terminal.terminalSize() else { return }

        terminalSize = (termSize.columns, termSize.rows)
        isResizing = true

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            isResizing = false
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func restartTerminal() {
        sessionManager.removeTerminal(for: workingDirectory)
        processExited = false
        focusVersion += 1
    }
}

// MARK: - Resize Overlay

struct ResizeOverlay: View {
    let columns: UInt16
    let rows: UInt16

    var body: some View {
        Text("\(columns) × \(rows)")
            .font(.system(size: 24, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
