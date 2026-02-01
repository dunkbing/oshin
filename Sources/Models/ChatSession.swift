//
//  ChatSession.swift
//  agentmonitor
//
//  Chat session model with persistence support
//

import Foundation

@MainActor
class ChatSession: ObservableObject, Identifiable {
    let id: UUID
    let repositoryPath: String
    let agentId: String
    @Published var title: String
    @Published var isActive: Bool = true
    let createdAt: Date
    @Published var updatedAt: Date

    /// Whether this session was restored from storage (has history)
    let isRestored: Bool

    /// Cached messages from storage (used when restoring)
    private(set) var cachedMessages: [MessageItem]?

    /// External session ID (e.g., from Claude Code's session history)
    let externalSessionId: String?

    /// Create a new chat session
    init(repositoryPath: String, agentId: String, title: String? = nil) {
        self.id = UUID()
        self.repositoryPath = repositoryPath
        self.agentId = agentId
        self.title = title ?? AgentRegistry.shared.getMetadata(for: agentId)?.name ?? agentId
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isRestored = false
        self.cachedMessages = nil
        self.externalSessionId = nil
    }

    /// Restore a session from stored conversation
    init(from stored: StoredConversation) {
        self.id = stored.id
        self.repositoryPath = stored.repositoryPath
        self.agentId = stored.agentId
        self.title = stored.title
        self.createdAt = stored.createdAt
        self.updatedAt = stored.updatedAt
        self.isRestored = true
        self.cachedMessages = stored.messages
        self.externalSessionId = nil
    }

    /// Create a session from Claude Code's session entry (loads messages from JSONL)
    init(from claudeSession: ClaudeSessionEntry, repositoryPath: String) {
        self.id = UUID()
        self.repositoryPath = repositoryPath
        self.agentId = "claude"
        self.title = ClaudeSessionStore.shared.getSessionSummary(claudeSession)
        self.createdAt = claudeSession.createdDate
        self.updatedAt = claudeSession.modifiedDate
        self.isRestored = true
        // Load messages from the JSONL file
        self.cachedMessages = ClaudeSessionStore.shared.loadSessionMessages(claudeSession)
        self.externalSessionId = claudeSession.sessionId
    }

    /// Create a session from Codex's session entry (loads messages from session file)
    init(from codexSession: CodexSessionEntry, repositoryPath: String) {
        self.id = UUID()
        self.repositoryPath = repositoryPath
        self.agentId = "codex"
        self.title = CodexSessionStore.shared.getSessionSummary(codexSession)
        self.createdAt = codexSession.createdAt
        self.updatedAt = codexSession.lastModified
        self.isRestored = true
        // Load messages from the session file
        self.cachedMessages = CodexSessionStore.shared.loadSessionMessages(
            codexSession.sessionId,
            filePath: codexSession.filePath
        )
        self.externalSessionId = codexSession.sessionId
    }

    /// Convert to storable format with current messages
    func toStored(messages: [MessageItem]) -> StoredConversation {
        StoredConversation(
            id: id,
            repositoryPath: repositoryPath,
            agentId: agentId,
            title: title,
            createdAt: createdAt,
            updatedAt: Date(),
            messages: messages
        )
    }

    /// Clear cached messages after they've been loaded into the agent session
    func clearCachedMessages() {
        cachedMessages = nil
    }
}
