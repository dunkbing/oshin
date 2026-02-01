//
//  ClaudeSessionStore.swift
//  agentmonitor
//
//  Reads Claude Code's session history from ~/.claude/projects/
//

import Foundation

// MARK: - Claude Session Index

struct ClaudeSessionIndex: Codable {
    let version: Int
    let entries: [ClaudeSessionEntry]
    let originalPath: String
}

struct ClaudeSessionEntry: Codable, Identifiable {
    let sessionId: String
    let fullPath: String
    let fileMtime: Int64
    let firstPrompt: String
    let summary: String
    let messageCount: Int
    let created: String
    let modified: String
    let gitBranch: String?
    let projectPath: String
    let isSidechain: Bool?

    var id: String { sessionId }

    var createdDate: Date {
        ISO8601DateFormatter().date(from: created) ?? Date()
    }

    var modifiedDate: Date {
        ISO8601DateFormatter().date(from: modified) ?? Date()
    }
}

// MARK: - Claude Session Store

@MainActor
class ClaudeSessionStore {
    static let shared = ClaudeSessionStore()

    private let fileManager = FileManager.default

    /// Claude's projects directory
    private var claudeProjectsDir: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects")
    }

    private init() {}

    // MARK: - Public API

    /// Load all session entries for a repository path
    func loadSessions(repositoryPath: String) -> [ClaudeSessionEntry] {
        let encodedPath = encodeProjectPath(repositoryPath)
        let projectDir = claudeProjectsDir.appendingPathComponent(encodedPath)
        let indexFile = projectDir.appendingPathComponent("sessions-index.json")

        guard fileManager.fileExists(atPath: indexFile.path) else {
            print("[ClaudeSessionStore] No sessions-index.json found at \(indexFile.path)")
            return []
        }

        do {
            let data = try Data(contentsOf: indexFile)
            let index = try JSONDecoder().decode(ClaudeSessionIndex.self, from: data)
            let sessions = index.entries.sorted { $0.modifiedDate > $1.modifiedDate }
            print("[ClaudeSessionStore] Loaded \(sessions.count) sessions for \(repositoryPath)")
            return sessions
        } catch {
            print("[ClaudeSessionStore] Failed to load sessions: \(error)")
            return []
        }
    }

    /// Get summary for displaying in the sidebar
    func getSessionSummary(_ entry: ClaudeSessionEntry) -> String {
        if !entry.summary.isEmpty {
            return entry.summary
        }
        // Fallback to first prompt truncated
        let prompt = entry.firstPrompt
        if prompt.count > 50 {
            return String(prompt.prefix(47)) + "..."
        }
        return prompt.isEmpty ? "Untitled" : prompt
    }

    /// Get the JSONL file path for a session
    func getSessionFilePath(_ entry: ClaudeSessionEntry) -> String {
        return entry.fullPath
    }

    /// Load messages from a session's JSONL file
    func loadSessionMessages(_ entry: ClaudeSessionEntry) -> [MessageItem] {
        return ClaudeSessionParser.shared.parseSession(filePath: entry.fullPath)
    }

    // MARK: - Private Helpers

    /// Encode project path the same way Claude Code does
    /// e.g., /Users/foo/bar -> -Users-foo-bar
    private func encodeProjectPath(_ path: String) -> String {
        return path.replacingOccurrences(of: "/", with: "-")
    }
}
