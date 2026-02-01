//
//  ChatContainerView.swift
//  oshin
//

import SwiftUI

// MARK: - Chat Container View

struct ChatContainerView: View {
    let workingDirectory: String

    @ObservedObject private var sessionManager = ChatSessionManager.shared
    @State private var selectedSessionId: UUID?
    @State private var showingAgentPicker = false
    @State private var showingSidebar = true
    @State private var sidebarAgentId: String? = "claude"

    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"

    private var sessions: [ChatSession] {
        sessionManager.getSessions(for: workingDirectory)
    }

    private var selectedSession: ChatSession? {
        sessions.first { $0.id == selectedSessionId }
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
                            currentAgentId: $sidebarAgentId,
                            selectedSessionId: $selectedSessionId,
                            onNewSession: {
                                if let agentId = sidebarAgentId {
                                    createNewSession(agentId: agentId)
                                }
                            },
                            onSelectSession: { session in
                                selectOrRestoreSession(session)
                            },
                            onSelectClaudeSession: { claudeSession in
                                selectClaudeSession(claudeSession)
                            },
                            onSelectCodexSession: { codexSession in
                                selectCodexSession(codexSession)
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

    private func selectCodexSession(_ codexSession: CodexSessionEntry) {
        // Check if we already have this session open
        if let existing = sessions.first(where: { $0.externalSessionId == codexSession.sessionId }) {
            selectedSessionId = existing.id
            return
        }

        // Create a new session from the Codex session entry (loads messages from history)
        let session = sessionManager.createSessionFromCodex(codexSession, repositoryPath: workingDirectory)
        selectedSessionId = session.id
    }
}
