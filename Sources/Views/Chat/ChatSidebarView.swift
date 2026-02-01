//
//  ChatSidebarView.swift
//  oshin
//

import SwiftUI

// MARK: - Chat Sidebar View

struct ChatSidebarView: View {
    let workingDirectory: String
    @Binding var currentAgentId: String?
    @Binding var selectedSessionId: UUID?
    let onNewSession: () -> Void
    let onSelectSession: (ChatSession) -> Void
    let onSelectClaudeSession: (ClaudeSessionEntry) -> Void
    let onSelectCodexSession: (CodexSessionEntry) -> Void
    let onDeleteSession: (ChatSession) -> Void

    @ObservedObject private var sessionManager = ChatSessionManager.shared
    @State private var hoveredSessionId: UUID?
    @State private var hoveredClaudeSessionId: String?
    @State private var hoveredCodexSessionId: String?
    @State private var conversationList: [ChatSession] = []
    @State private var claudeSessions: [ClaudeSessionEntry] = []
    @State private var codexSessions: [CodexSessionEntry] = []

    private var agentMetadata: AgentMetadata? {
        guard let agentId = currentAgentId else { return nil }
        return AgentRegistry.shared.getMetadata(for: agentId)
    }

    private var availableAgents: [AgentMetadata] {
        AgentRegistry.shared.getEnabledAgents()
    }

    private var isClaudeAgent: Bool {
        currentAgentId == "claude"
    }

    private var isCodexAgent: Bool {
        currentAgentId == "codex"
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
            Menu {
                ForEach(availableAgents, id: \.id) { agent in
                    Button {
                        currentAgentId = agent.id
                    } label: {
                        HStack {
                            AgentIconView(iconType: agent.iconType, size: 14)
                            Text(agent.name)
                            if currentAgentId == agent.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let metadata = agentMetadata {
                        AgentIconView(iconType: metadata.iconType, size: 16)
                        Text(metadata.name)
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Text("Select Agent")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

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
        } else if isCodexAgent {
            codexSessionListView
        } else {
            customSessionListView
        }
    }

    @ViewBuilder
    private var claudeSessionListView: some View {
        if claudeSessions.isEmpty {
            emptyStateView
        } else {
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

    @ViewBuilder
    private var codexSessionListView: some View {
        if codexSessions.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(codexSessions) { session in
                        CodexSessionRowView(
                            session: session,
                            isHovered: hoveredCodexSessionId == session.id,
                            onSelect: { onSelectCodexSession(session) }
                        )
                        .onHover { hovering in
                            hoveredCodexSessionId = hovering ? session.id : nil
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
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
            conversationList = []
            claudeSessions = []
            codexSessions = []
            return
        }

        conversationList = []
        claudeSessions = []
        codexSessions = []

        if agentId == "claude" {
            claudeSessions = ClaudeSessionStore.shared.loadSessions(repositoryPath: workingDirectory)
        } else if agentId == "codex" {
            codexSessions = CodexSessionStore.shared.loadSessions(repositoryPath: workingDirectory)
        } else {
            conversationList = sessionManager.getConversationHistory(for: workingDirectory, agentId: agentId)
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
        .help("Resume session")
    }
}

// MARK: - Codex Session Row View

struct CodexSessionRowView: View {
    let session: CodexSessionEntry
    let isHovered: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CodexSessionStore.shared.getSessionSummary(session))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(DateFormatters.relative.string(from: session.lastModified))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

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
        .help("Resume session")
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
