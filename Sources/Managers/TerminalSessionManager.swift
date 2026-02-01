//
//  TerminalSessionManager.swift
//  oshin
//
//  Manages terminal sessions and caches terminal instances
//

import AppKit
import Foundation

@MainActor
class TerminalSessionManager: ObservableObject {
    static let shared = TerminalSessionManager()

    // Sessions per repository path
    @Published private(set) var sessions: [String: [TerminalSession]] = [:]

    // Terminals keyed by session ID
    private var terminals: [UUID: GhosttyTerminalView] = [:]
    private var scrollViews: [UUID: TerminalScrollView] = [:]

    private init() {}

    // MARK: - Session Management

    func getSessions(for repositoryPath: String) -> [TerminalSession] {
        return sessions[repositoryPath] ?? []
    }

    func createSession(for repositoryPath: String, title: String? = nil) -> TerminalSession {
        let count = (sessions[repositoryPath]?.count ?? 0) + 1
        let session = TerminalSession(
            repositoryPath: repositoryPath,
            title: title ?? "Terminal \(count)"
        )

        if sessions[repositoryPath] == nil {
            sessions[repositoryPath] = []
        }
        sessions[repositoryPath]?.append(session)

        return session
    }

    func removeSession(_ session: TerminalSession) {
        let path = session.repositoryPath

        // Clean up terminal
        if let terminal = terminals.removeValue(forKey: session.id) {
            terminal.onProcessExit = nil
            terminal.onTitleChange = nil
        }
        scrollViews.removeValue(forKey: session.id)

        // Remove session from list
        sessions[path]?.removeAll { $0.id == session.id }
    }

    func removeAllSessions(for repositoryPath: String) {
        guard let repoSessions = sessions[repositoryPath] else { return }

        for session in repoSessions {
            if let terminal = terminals.removeValue(forKey: session.id) {
                terminal.onProcessExit = nil
                terminal.onTitleChange = nil
            }
            scrollViews.removeValue(forKey: session.id)
        }

        sessions.removeValue(forKey: repositoryPath)
    }

    // MARK: - Terminal Management

    func getTerminal(for sessionId: UUID) -> GhosttyTerminalView? {
        return terminals[sessionId]
    }

    func setTerminal(_ terminal: GhosttyTerminalView, for sessionId: UUID) {
        terminals[sessionId] = terminal
    }

    func getScrollView(for sessionId: UUID) -> TerminalScrollView? {
        return scrollViews[sessionId]
    }

    func setScrollView(_ scrollView: TerminalScrollView, for sessionId: UUID) {
        scrollViews[sessionId] = scrollView
    }

    // MARK: - Cleanup

    func removeAll() {
        for (_, terminal) in terminals {
            terminal.onProcessExit = nil
            terminal.onTitleChange = nil
        }
        terminals.removeAll()
        scrollViews.removeAll()
        sessions.removeAll()
    }
}
