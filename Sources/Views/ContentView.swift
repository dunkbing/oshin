import SwiftData
import SwiftUI

// MARK: - Detail Tab

enum DetailTab: String, CaseIterable {
    case git
    case chat
    case terminal

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
            Spacer()
                .frame(height: 32)

            switch selectedTab {
            case .chat:
                ChatContainerView(workingDirectory: repository.path)
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
        .toolbar {
            ToolbarItem(placement: .navigation) {
                DetailTabBar(selectedTab: $selectedTab)
            }
        }
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

// MARK: - Chat Container View

struct ChatContainerView: View {
    let workingDirectory: String

    @ObservedObject private var sessionManager = ChatSessionManager.shared
    @State private var selectedSessionId: UUID?
    @State private var showingAgentPicker = false

    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"

    private var sessions: [ChatSession] {
        sessionManager.getSessions(for: workingDirectory)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            ChatTabBar(
                sessions: sessions,
                selectedSessionId: $selectedSessionId,
                showingAgentPicker: $showingAgentPicker,
                onClose: { session in
                    closeSession(session)
                },
                onSelect: { agentId in
                    createNewSession(agentId: agentId)
                }
            )

            Divider()

            // Chat content
            if sessions.isEmpty {
                chatEmptyState
            } else {
                ZStack {
                    ForEach(sessions) { session in
                        let isSelected = selectedSessionId == session.id
                        ChatTabView(
                            chatSession: session,
                            sessionManager: sessionManager,
                            isSelected: isSelected
                        )
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(isSelected)
                        .zIndex(isSelected ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if sessions.isEmpty {
                createNewSession(agentId: defaultACPAgent)
            } else if selectedSessionId == nil {
                selectedSessionId = sessions.first?.id
            }
        }
    }

    @State private var showingEmptyStatePopover = false

    private var chatEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("No Chat Sessions")
                .font(.title2)
                .fontWeight(.semibold)

            Button {
                showingEmptyStatePopover = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("New Chat")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingEmptyStatePopover, arrowEdge: .bottom) {
                AgentPickerPopover { agentId in
                    createNewSession(agentId: agentId)
                    showingEmptyStatePopover = false
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createNewSession(agentId: String) {
        let session = sessionManager.createSession(for: workingDirectory, agentId: agentId)
        selectedSessionId = session.id
    }

    private func closeSession(_ session: ChatSession) {
        let wasSelected = selectedSessionId == session.id
        sessionManager.removeSession(session)

        if wasSelected {
            selectedSessionId = sessions.first?.id
        }
    }
}

// MARK: - Chat Tab Bar

struct ChatTabBar: View {
    let sessions: [ChatSession]
    @Binding var selectedSessionId: UUID?
    @Binding var showingAgentPicker: Bool
    let onClose: (ChatSession) -> Void
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(sessions) { session in
                        ChatTabButton(
                            session: session,
                            isSelected: selectedSessionId == session.id,
                            onSelect: { selectedSessionId = session.id },
                            onClose: { onClose(session) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // New tab button with popover
            Button {
                showingAgentPicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .popover(isPresented: $showingAgentPicker, arrowEdge: .bottom) {
                AgentPickerPopover { agentId in
                    onSelect(agentId)
                    showingAgentPicker = false
                }
            }
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Chat Tab Button

struct ChatTabButton: View {
    @ObservedObject var session: ChatSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Close button
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                        .background(
                            Circle()
                                .fill(isHovering ? Color.primary.opacity(0.1) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isSelected ? 1 : 0)

                // Agent icon
                if let metadata = AgentRegistry.shared.getMetadata(for: session.agentId) {
                    AgentIconView(iconType: metadata.iconType, size: 14)
                }

                Text(session.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 100)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.primary.opacity(0.1) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(session.title)
    }
}

// MARK: - Agent Picker Popover

struct AgentPickerPopover: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AgentRegistry.shared.getEnabledAgents(), id: \.id) { agent in
                Button {
                    onSelect(agent.id)
                } label: {
                    HStack(spacing: 8) {
                        AgentIconView(iconType: agent.iconType, size: 16)

                        Text(agent.name)
                            .font(.system(size: 12))

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.001))
                .cornerRadius(4)
            }
        }
        .padding(8)
        .frame(width: 160)
    }
}

// MARK: - Terminal Tab

struct TerminalTabView: View {
    let workingDirectory: String
    @ObservedObject var ghosttyApp: Ghostty.App

    @ObservedObject private var sessionManager = TerminalSessionManager.shared
    @State private var selectedSessionId: UUID?

    private var sessions: [TerminalSession] {
        sessionManager.getSessions(for: workingDirectory)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            TerminalTabBar(
                sessions: sessions,
                selectedSessionId: $selectedSessionId,
                onClose: { session in
                    closeSession(session)
                },
                onAdd: {
                    createNewSession()
                }
            )

            Divider()

            // Terminal content
            if sessions.isEmpty {
                terminalEmptyState
            } else {
                ZStack {
                    ForEach(sessions) { session in
                        let isSelected = selectedSessionId == session.id
                        TerminalPaneView(
                            session: session,
                            ghosttyApp: ghosttyApp,
                            sessionManager: sessionManager,
                            isSelected: isSelected,
                            onClose: {
                                closeSession(session)
                            }
                        )
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(isSelected)
                        .zIndex(isSelected ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Create initial session if none exist
            if sessions.isEmpty {
                createNewSession()
            } else if selectedSessionId == nil {
                selectedSessionId = sessions.first?.id
            }
        }
    }

    private var terminalEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "terminal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("No Terminal Sessions")
                .font(.title2)
                .fontWeight(.semibold)

            Button {
                createNewSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("New Terminal")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createNewSession() {
        let session = sessionManager.createSession(for: workingDirectory)
        selectedSessionId = session.id
    }

    private func closeSession(_ session: TerminalSession) {
        let wasSelected = selectedSessionId == session.id
        sessionManager.removeSession(session)

        if wasSelected {
            selectedSessionId = sessions.first?.id
        }
    }
}

// MARK: - Terminal Tab Bar

struct TerminalTabBar: View {
    let sessions: [TerminalSession]
    @Binding var selectedSessionId: UUID?
    let onClose: (TerminalSession) -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(sessions) { session in
                        TerminalTabButton(
                            session: session,
                            isSelected: selectedSessionId == session.id,
                            onSelect: { selectedSessionId = session.id },
                            onClose: { onClose(session) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // New tab button
            Button {
                onAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Terminal Tab Button

struct TerminalTabButton: View {
    @ObservedObject var session: TerminalSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Close button
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                        .background(
                            Circle()
                                .fill(isHovering ? Color.primary.opacity(0.1) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isSelected ? 1 : 0)

                Image(systemName: "terminal")
                    .font(.system(size: 11))

                Text(session.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 100)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.primary.opacity(0.1) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(session.title)
    }
}

// MARK: - Terminal Pane View

struct TerminalPaneView: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var ghosttyApp: Ghostty.App
    let sessionManager: TerminalSessionManager
    let isSelected: Bool
    let onClose: () -> Void

    @State private var shouldFocus: Bool = false
    @State private var focusVersion: Int = 0
    @State private var isResizing: Bool = false
    @State private var terminalSize: (columns: UInt16, rows: UInt16) = (0, 0)
    @State private var hideWorkItem: DispatchWorkItem?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TerminalViewWrapper(
                    session: session,
                    ghosttyApp: ghosttyApp,
                    sessionManager: sessionManager,
                    onProcessExit: {
                        onClose()
                    },
                    onTitleChange: { title in
                        session.title = title
                    },
                    shouldFocus: shouldFocus,
                    isFocused: isSelected,
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
            }
            .onChange(of: geo.size) { _, _ in
                handleSizeChange()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    shouldFocus = true
                    focusVersion += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        shouldFocus = false
                    }
                }
            }
        }
        .onAppear {
            if isSelected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    shouldFocus = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        shouldFocus = false
                    }
                }
            }
        }
        .onDisappear {
            hideWorkItem?.cancel()
            hideWorkItem = nil
        }
    }

    private func handleSizeChange() {
        guard let terminal = sessionManager.getTerminal(for: session.id),
            let termSize = terminal.terminalSize()
        else { return }

        terminalSize = (termSize.columns, termSize.rows)
        isResizing = true

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            isResizing = false
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
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

    @State private var sidebarTab: GitSidebarTab = .changes

    var body: some View {
        VStack(spacing: 0) {
            GitTabHeader(repository: repository)

            Divider()

            if gitService.isLoading {
                ProgressView("Loading git status...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    GitSidebarView(
                        selectedFile: selectedFile,
                        onFileClick: { file in
                            selectedFile = file
                            Task {
                                await gitService.loadFileDiff(for: file)
                            }
                        },
                        sidebarTab: $sidebarTab
                    )
                    .frame(minWidth: 250, idealWidth: 300)

                    // Right panel content based on selected tab
                    switch sidebarTab {
                    case .changes:
                        DiffView(
                            diffOutput: gitService.selectedFileDiff,
                            fileName: selectedFile ?? "",
                            fontSize: diffFontSize
                        )
                        .frame(minWidth: 400)
                    case .history:
                        CommitDetailView(fontSize: diffFontSize)
                            .frame(minWidth: 400)
                    }
                }
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
