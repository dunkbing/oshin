//
//  ChatSessionManager.swift
//  agentmonitor
//
//  Manages chat sessions and caches agent session instances
//

import Foundation

@MainActor
class ChatSessionManager: ObservableObject {
    static let shared = ChatSessionManager()

    // Sessions per repository path
    @Published private(set) var sessions: [String: [ChatSession]] = [:]

    // AgentSessions keyed by chat session ID
    private var agentSessions: [UUID: AgentSession] = [:]

    private init() {}

    // MARK: - Session Management

    func getSessions(for repositoryPath: String) -> [ChatSession] {
        return sessions[repositoryPath] ?? []
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

    func removeSession(_ session: ChatSession) {
        let path = session.repositoryPath

        // Clean up agent session
        if let agentSession = agentSessions.removeValue(forKey: session.id) {
            Task {
                await agentSession.close()
            }
        }

        // Remove session from list
        sessions[path]?.removeAll { $0.id == session.id }
    }

    func removeAllSessions(for repositoryPath: String) {
        guard let repoSessions = sessions[repositoryPath] else { return }

        for session in repoSessions {
            if let agentSession = agentSessions.removeValue(forKey: session.id) {
                Task {
                    await agentSession.close()
                }
            }
        }

        sessions.removeValue(forKey: repositoryPath)
    }

    // MARK: - Agent Session Management

    func getAgentSession(for sessionId: UUID) -> AgentSession? {
        return agentSessions[sessionId]
    }

    func setAgentSession(_ agentSession: AgentSession, for sessionId: UUID) {
        agentSessions[sessionId] = agentSession
    }

    // MARK: - Cleanup

    func removeAll() {
        for (_, agentSession) in agentSessions {
            Task {
                await agentSession.close()
            }
        }
        agentSessions.removeAll()
        sessions.removeAll()
    }
}
