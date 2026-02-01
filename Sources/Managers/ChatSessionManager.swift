//
//  ChatSessionManager.swift
//  agentmonitor
//
//  Manages chat sessions with persistence support
//

import Combine
import Foundation

@MainActor
class ChatSessionManager: ObservableObject {
    static let shared = ChatSessionManager()

    // Sessions per repository path (active sessions only)
    @Published private(set) var sessions: [String: [ChatSession]] = [:]

    // AgentSessions keyed by chat session ID
    private var agentSessions: [UUID: AgentSession] = [:]

    // Cancellables for observing message changes
    private var messageCancellables: [UUID: AnyCancellable] = [:]

    private let store = ConversationStore.shared

    private init() {}

    // MARK: - Session Management

    func getSessions(for repositoryPath: String) -> [ChatSession] {
        return sessions[repositoryPath] ?? []
    }

    /// Get all conversations (including history) for a repository and agent
    func getConversationHistory(for repositoryPath: String, agentId: String) -> [ChatSession] {
        print("[ChatSessionManager] getConversationHistory: repositoryPath=\(repositoryPath), agentId=\(agentId)")
        let stored = store.loadConversations(repositoryPath: repositoryPath, agentId: agentId)
        print("[ChatSessionManager] getConversationHistory: loaded \(stored.count) from store")
        let activeSessions = getSessions(for: repositoryPath).filter { $0.agentId == agentId }
        print("[ChatSessionManager] getConversationHistory: \(activeSessions.count) active sessions")

        // Combine active sessions with stored ones (avoiding duplicates)
        let activeIds = Set(activeSessions.map { $0.id })
        let historySessions =
            stored
            .filter { !activeIds.contains($0.id) }
            .map { ChatSession(from: $0) }

        // Return active sessions first, then history (sorted by updatedAt)
        let result = (activeSessions + historySessions).sorted { $0.updatedAt > $1.updatedAt }
        print("[ChatSessionManager] getConversationHistory: returning \(result.count) total")
        return result
    }

    func createSession(for repositoryPath: String, agentId: String) -> ChatSession {
        let session = ChatSession(
            repositoryPath: repositoryPath,
            agentId: agentId
        )

        if sessions[repositoryPath] == nil {
            sessions[repositoryPath] = []
        }
        sessions[repositoryPath]?.append(session)

        return session
    }

    /// Restore a session from history
    func restoreSession(_ stored: StoredConversation) -> ChatSession {
        let session = ChatSession(from: stored)
        let path = session.repositoryPath

        if sessions[path] == nil {
            sessions[path] = []
        }

        // Check if session already exists in active sessions
        if let existingIndex = sessions[path]?.firstIndex(where: { $0.id == session.id }) {
            return sessions[path]![existingIndex]
        }

        sessions[path]?.append(session)
        return session
    }

    /// Create a session from Claude Code's session history
    func createSessionFromClaude(_ claudeSession: ClaudeSessionEntry, repositoryPath: String) -> ChatSession {
        // Check if we already have an active session with this external ID
        if let existingSessions = sessions[repositoryPath] {
            if let existing = existingSessions.first(where: { $0.externalSessionId == claudeSession.sessionId }) {
                return existing
            }
        }

        let session = ChatSession(from: claudeSession, repositoryPath: repositoryPath)

        if sessions[repositoryPath] == nil {
            sessions[repositoryPath] = []
        }
        sessions[repositoryPath]?.append(session)

        return session
    }

    func removeSession(_ session: ChatSession) {
        let path = session.repositoryPath

        // Clean up agent session
        if let agentSession = agentSessions.removeValue(forKey: session.id) {
            // Save conversation before closing
            saveConversation(for: session, messages: agentSession.messages)

            Task {
                await agentSession.close()
            }
        }

        // Remove message observer
        messageCancellables.removeValue(forKey: session.id)

        // Remove session from list
        sessions[path]?.removeAll { $0.id == session.id }
    }

    /// Delete a session and its persisted data
    func deleteSession(_ session: ChatSession) {
        removeSession(session)
        store.deleteConversation(id: session.id, repositoryPath: session.repositoryPath)
    }

    func removeAllSessions(for repositoryPath: String) {
        guard let repoSessions = sessions[repositoryPath] else { return }

        for session in repoSessions {
            if let agentSession = agentSessions.removeValue(forKey: session.id) {
                // Save before closing
                saveConversation(for: session, messages: agentSession.messages)

                Task {
                    await agentSession.close()
                }
            }
            messageCancellables.removeValue(forKey: session.id)
        }

        sessions.removeValue(forKey: repositoryPath)
    }

    // MARK: - Agent Session Management

    func getAgentSession(for sessionId: UUID) -> AgentSession? {
        return agentSessions[sessionId]
    }

    func setAgentSession(_ agentSession: AgentSession, for sessionId: UUID) {
        agentSessions[sessionId] = agentSession

        // Find the chat session and restore cached messages if available
        for (_, sessionList) in sessions {
            if let chatSession = sessionList.first(where: { $0.id == sessionId }) {
                if let cachedMessages = chatSession.cachedMessages {
                    // Restore messages to the agent session
                    agentSession.restoreMessages(cachedMessages)
                    chatSession.clearCachedMessages()
                }
                break
            }
        }

        // Observe message changes for auto-save
        observeMessages(for: sessionId, agentSession: agentSession)
    }

    // MARK: - Persistence

    private func observeMessages(for sessionId: UUID, agentSession: AgentSession) {
        // Debounce saves to avoid too frequent writes
        messageCancellables[sessionId] = agentSession.$messages
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] messages in
                guard let self = self else { return }
                self.saveSessionIfNeeded(sessionId: sessionId, messages: messages)
            }
    }

    private func saveSessionIfNeeded(sessionId: UUID, messages: [MessageItem]) {
        // Find the chat session
        for (_, sessionList) in sessions {
            if let session = sessionList.first(where: { $0.id == sessionId }) {
                // Only save if there are messages
                if !messages.isEmpty {
                    saveConversation(for: session, messages: messages)
                }
                break
            }
        }
    }

    private func saveConversation(for session: ChatSession, messages: [MessageItem]) {
        let stored = session.toStored(messages: messages)
        store.saveConversation(stored)
        session.updatedAt = Date()
    }

    /// Force save all active sessions
    func saveAllSessions() {
        for (_, sessionList) in sessions {
            for session in sessionList {
                if let agentSession = agentSessions[session.id] {
                    saveConversation(for: session, messages: agentSession.messages)
                }
            }
        }
    }

    // MARK: - Cleanup

    func removeAll() {
        // Save all sessions before removing
        saveAllSessions()

        for (_, agentSession) in agentSessions {
            Task {
                await agentSession.close()
            }
        }
        agentSessions.removeAll()
        messageCancellables.removeAll()
        sessions.removeAll()
    }
}
