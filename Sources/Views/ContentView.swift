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
            case .git:
                GitTabView(
                    repository: repository,
                    selectedFile: $selectedFile,
                    diffFontSize: diffFontSize
                )
            case .chat:
                ChatContainerView(workingDirectory: repository.path)
            case .terminal:
                TerminalTabView(workingDirectory: repository.path, ghosttyApp: ghosttyApp)
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
    @State private var showingSidebar = true

    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"

    private var sessions: [ChatSession] {
        sessionManager.getSessions(for: workingDirectory)
    }

    private var selectedSession: ChatSession? {
        sessions.first { $0.id == selectedSessionId }
    }

    /// All conversations (active + history) for the current agent
    private var conversationHistory: [ChatSession] {
        guard let currentAgentId = selectedSession?.agentId else { return [] }
        return sessionManager.getConversationHistory(for: workingDirectory, agentId: currentAgentId)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            ChatTabBar(
                sessions: sessions,
                selectedSessionId: $selectedSessionId,
                showingAgentPicker: $showingAgentPicker,
                showingSidebar: $showingSidebar,
                onClose: { session in
                    closeSession(session)
                },
                onSelect: { agentId in
                    createNewSession(agentId: agentId)
                }
            )

            Divider()

            // Chat content with sidebar
            if sessions.isEmpty {
                chatEmptyState
            } else {
                HSplitView {
                    // Sidebar - conversation history
                    if showingSidebar {
                        ChatSidebarView(
                            workingDirectory: workingDirectory,
                            currentAgentId: selectedSession?.agentId,
                            selectedSessionId: $selectedSessionId,
                            onNewSession: {
                                if let agentId = selectedSession?.agentId {
                                    createNewSession(agentId: agentId)
                                }
                            },
                            onSelectSession: { session in
                                selectOrRestoreSession(session)
                            },
                            onSelectClaudeSession: { claudeSession in
                                selectClaudeSession(claudeSession)
                            },
                            onDeleteSession: { session in
                                deleteSession(session)
                            }
                        )
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                    }

                    // Main chat area
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

    private func selectOrRestoreSession(_ session: ChatSession) {
        // If session is already in active sessions, just select it
        if sessions.contains(where: { $0.id == session.id }) {
            selectedSessionId = session.id
        } else {
            // Need to restore from history - get the stored conversation
            if let stored = ConversationStore.shared.getConversation(
                id: session.id,
                repositoryPath: workingDirectory
            ) {
                let restoredSession = sessionManager.restoreSession(stored)
                selectedSessionId = restoredSession.id
            }
        }
    }

    private func deleteSession(_ session: ChatSession) {
        let wasSelected = selectedSessionId == session.id
        sessionManager.deleteSession(session)

        if wasSelected {
            selectedSessionId = sessions.first?.id
        }
    }

    private func selectClaudeSession(_ claudeSession: ClaudeSessionEntry) {
        // Check if we already have this session open
        if let existing = sessions.first(where: { $0.externalSessionId == claudeSession.sessionId }) {
            selectedSessionId = existing.id
            return
        }

        // Create a new session from the Claude session entry (loads messages from JSONL)
        let session = sessionManager.createSessionFromClaude(claudeSession, repositoryPath: workingDirectory)
        selectedSessionId = session.id
    }
}

// MARK: - Chat Sidebar View

struct ChatSidebarView: View {
    let workingDirectory: String
    let currentAgentId: String?
    @Binding var selectedSessionId: UUID?
    let onNewSession: () -> Void
    let onSelectSession: (ChatSession) -> Void
    let onSelectClaudeSession: (ClaudeSessionEntry) -> Void
    let onDeleteSession: (ChatSession) -> Void

    @ObservedObject private var sessionManager = ChatSessionManager.shared
    @State private var hoveredSessionId: UUID?
    @State private var hoveredClaudeSessionId: String?
    @State private var conversationList: [ChatSession] = []
    @State private var claudeSessions: [ClaudeSessionEntry] = []

    private var agentMetadata: AgentMetadata? {
        guard let agentId = currentAgentId else { return nil }
        return AgentRegistry.shared.getMetadata(for: agentId)
    }

    /// Check if current agent is Claude (to load from Claude Code's storage)
    private var isClaudeAgent: Bool {
        currentAgentId == "claude"
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()
            conversationListView
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            loadConversations()
        }
        .onChange(of: currentAgentId) { _, _ in
            loadConversations()
        }
        .onReceive(sessionManager.objectWillChange) { _ in
            loadConversations()
        }
    }

    private var sidebarHeader: some View {
        HStack {
            if let metadata = agentMetadata {
                AgentIconView(iconType: metadata.iconType, size: 16)
                Text(metadata.name)
                    .font(.system(size: 12, weight: .semibold))
            } else {
                Text("Conversations")
                    .font(.system(size: 12, weight: .semibold))
            }

            Spacer()

            Button(action: onNewSession) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New conversation")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var conversationListView: some View {
        if isClaudeAgent {
            claudeSessionListView
        } else {
            customSessionListView
        }
    }

    @ViewBuilder
    private var claudeSessionListView: some View {
        if claudeSessions.isEmpty {
            emptyStateView
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Info banner
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text("History is read-only (resume not yet supported)")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(claudeSessions) { session in
                            ClaudeSessionRowView(
                                session: session,
                                isHovered: hoveredClaudeSessionId == session.id,
                                onSelect: { onSelectClaudeSession(session) }
                            )
                            .onHover { hovering in
                                hoveredClaudeSessionId = hovering ? session.id : nil
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var customSessionListView: some View {
        if conversationList.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(conversationList) { session in
                        ChatSidebarRowView(
                            session: session,
                            isSelected: selectedSessionId == session.id,
                            isHovered: hoveredSessionId == session.id,
                            onSelect: { onSelectSession(session) },
                            onDelete: { onDeleteSession(session) }
                        )
                        .onHover { hovering in
                            hoveredSessionId = hovering ? session.id : nil
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No conversations")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func loadConversations() {
        guard let agentId = currentAgentId else {
            print("[ChatSidebarView] loadConversations: currentAgentId is nil")
            conversationList = []
            claudeSessions = []
            return
        }

        if agentId == "claude" {
            // Load from Claude Code's storage
            claudeSessions = ClaudeSessionStore.shared.loadSessions(repositoryPath: workingDirectory)
            print("[ChatSidebarView] loadConversations: loaded \(claudeSessions.count) Claude sessions")
        } else {
            // Load from our custom storage
            print("[ChatSidebarView] loadConversations: loading for agentId=\(agentId)")
            conversationList = sessionManager.getConversationHistory(for: workingDirectory, agentId: agentId)
            print("[ChatSidebarView] loadConversations: got \(conversationList.count) conversations")
        }
    }
}

// MARK: - Claude Session Row View

struct ClaudeSessionRowView: View {
    let session: ClaudeSessionEntry
    let isHovered: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ClaudeSessionStore.shared.getSessionSummary(session))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(DateFormatters.relative.string(from: session.modifiedDate))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    if let branch = session.gitBranch, !branch.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 8))
                            Text(branch)
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text("\(session.messageCount) msgs")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to view session history")
    }
}

// MARK: - Chat Sidebar Row View

struct ChatSidebarRowView: View {
    @ObservedObject var session: ChatSession
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    private var activeSessions: [ChatSession] {
        ChatSessionManager.shared.getSessions(for: session.repositoryPath)
    }

    private var isActive: Bool {
        activeSessions.contains { $0.id == session.id }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(session.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        // Show indicator for active sessions
                        if isActive {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                    }

                    Text(DateFormatters.relative.string(from: session.updatedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if isHovered || isSelected {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.15)
                            : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat Tab Bar

struct ChatTabBar: View {
    let sessions: [ChatSession]
    @Binding var selectedSessionId: UUID?
    @Binding var showingAgentPicker: Bool
    @Binding var showingSidebar: Bool
    let onClose: (ChatSession) -> Void
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar toggle button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSidebar.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .foregroundStyle(showingSidebar ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .help(showingSidebar ? "Hide sidebar" : "Show sidebar")

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 6)

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

            GitSidebarTabPicker(selectedTab: $sidebarTab)

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

    @State private var showingBranchPicker = false

    private var gitStatus: GitStatus { gitService.currentStatus }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(repository.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(repository.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if gitStatus.hasChanges {
                GitStatusView(
                    additions: gitStatus.additions,
                    deletions: gitStatus.deletions,
                    untrackedFiles: gitStatus.untrackedFiles.count
                )
            }

            Spacer()

            // Branch selector
            if !gitStatus.currentBranch.isEmpty {
                Button {
                    showingBranchPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(gitStatus.currentBranch)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingBranchPicker, arrowEdge: .bottom) {
                    BranchPickerPopover(
                        currentBranch: gitStatus.currentBranch,
                        onSelect: { branch in
                            gitService.checkout(branch: branch)
                            showingBranchPicker = false
                        }
                    )
                }
            }

            // Remote operations
            HStack(spacing: 4) {
                Button {
                    gitService.fetch()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("Fetch")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help("Fetch from remote")

                Button {
                    gitService.pull()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.to.line")
                        Text("Pull")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help("Pull from remote")

                Button {
                    gitService.push()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.to.line")
                        Text("Push")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help("Push to remote")
            }
            .disabled(gitService.isOperationPending)

            Divider()
                .frame(height: 20)

            // Refresh button
            Button {
                Task {
                    await gitService.reloadStatus()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refresh")
            .disabled(gitService.isLoading || gitService.isOperationPending)
        }
        .padding()
    }
}

// MARK: - Branch Picker Popover

struct BranchPickerPopover: View {
    @EnvironmentObject private var gitService: GitService

    let currentBranch: String
    let onSelect: (String) -> Void

    @State private var searchText = ""

    private var filteredBranches: [BranchInfo] {
        if searchText.isEmpty {
            return gitService.branches
        }
        return gitService.branches.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search branches...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)

            Divider()

            // Branch list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredBranches) { branch in
                        Button {
                            onSelect(branch.name)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: branch.isRemote ? "cloud" : "arrow.triangle.branch")
                                    .font(.system(size: 11))
                                    .foregroundStyle(branch.isRemote ? .blue : .secondary)
                                    .frame(width: 16)

                                Text(branch.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)

                                Spacer()

                                if branch.name == currentBranch {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            branch.name == currentBranch
                                ? Color.blue.opacity(0.1) : Color.clear
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 250)
        .onAppear {
            Task {
                await gitService.loadBranches()
            }
        }
    }
}
