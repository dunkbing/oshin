//
//  CodexSessionStore.swift
//  oshin
//
//  Reads Codex session history from ~/.codex/sessions/
//  Codex uses a different protocol than Claude (thread/* vs session/*)
//

import Foundation

// MARK: - Codex Session Meta (from session files)

struct CodexSessionMeta: Codable {
    let id: String
    let timestamp: String
    let cwd: String
}

struct CodexSessionMetaEntry: Codable {
    let timestamp: String
    let type: String
    let payload: CodexSessionMeta?
}

// MARK: - Codex Event Message (for extracting conversation)

struct CodexEventMsg: Codable {
    let timestamp: String
    let type: String
    let payload: CodexEventPayload?
}

struct CodexEventPayload: Codable {
    let type: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case type, message
    }
}

// MARK: - Codex Session Entry

struct CodexSessionEntry: Identifiable {
    let sessionId: String
    let firstPrompt: String
    let messageCount: Int
    let createdAt: Date
    let lastModified: Date
    let cwd: String
    let filePath: String

    var id: String { sessionId }

    var summary: String {
        if firstPrompt.count > 50 {
            return String(firstPrompt.prefix(47)) + "..."
        }
        return firstPrompt.isEmpty ? "Untitled" : firstPrompt
    }
}

// MARK: - Codex Session Store

@MainActor
class CodexSessionStore {
    static let shared = CodexSessionStore()

    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()

    /// Codex home directory
    private var codexHomeDir: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        // Check CODEX_HOME env var first
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"] {
            return URL(fileURLWithPath: codexHome)
        }
        return home.appendingPathComponent(".codex")
    }

    private init() {}

    // MARK: - Public API

    /// Load all session entries filtered by repository path
    func loadSessions(repositoryPath: String) -> [CodexSessionEntry] {
        let sessionsDir = codexHomeDir.appendingPathComponent("sessions")

        guard fileManager.fileExists(atPath: sessionsDir.path) else {
            print("[CodexSessionStore] Sessions directory not found")
            return []
        }

        var sessions: [CodexSessionEntry] = []

        // Recursively find all .jsonl files in the sessions directory
        guard
            let enumerator = fileManager.enumerator(
                at: sessionsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            // Parse the session file
            guard let sessionEntry = parseSessionFile(fileURL, repositoryPath: repositoryPath) else {
                continue
            }

            sessions.append(sessionEntry)
        }

        // Sort by last modified (most recent first)
        sessions.sort { $0.lastModified > $1.lastModified }

        print("[CodexSessionStore] Loaded \(sessions.count) sessions for \(repositoryPath)")
        return sessions
    }

    /// Get summary for displaying in the sidebar
    func getSessionSummary(_ entry: CodexSessionEntry) -> String {
        return entry.summary
    }

    /// Load messages from a session file
    func loadSessionMessages(_ sessionId: String, filePath: String) -> [MessageItem] {
        guard fileManager.fileExists(atPath: filePath) else {
            return []
        }

        guard let data = fileManager.contents(atPath: filePath),
            let content = String(data: data, encoding: .utf8)
        else {
            return []
        }

        let lines = content.components(separatedBy: .newlines)
        var messages: [MessageItem] = []

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8) else { continue }

            do {
                let entry = try decoder.decode(CodexEventMsg.self, from: lineData)

                // Only process event_msg entries with user_message or agent_message
                guard entry.type == "event_msg",
                    let payload = entry.payload,
                    let messageType = payload.type,
                    let messageText = payload.message,
                    !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }

                let role: MessageRole
                switch messageType {
                case "user_message":
                    role = .user
                case "agent_message":
                    role = .agent
                default:
                    continue
                }

                let timestamp = ISO8601DateFormatter().date(from: entry.timestamp) ?? Date()
                let message = MessageItem(
                    id: "\(sessionId)-\(entry.timestamp)",
                    role: role,
                    content: messageText,
                    timestamp: timestamp,
                    isComplete: true
                )
                messages.append(message)
            } catch {
                continue
            }
        }

        print("[CodexSessionStore] Loaded \(messages.count) messages for session \(sessionId)")
        return messages
    }

    // MARK: - Private Methods

    /// Parse a session file and return a CodexSessionEntry if it matches the repository path
    private func parseSessionFile(_ fileURL: URL, repositoryPath: String) -> CodexSessionEntry? {
        guard let data = fileManager.contents(atPath: fileURL.path),
            let content = String(data: data, encoding: .utf8)
        else { return nil }

        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return nil }

        // Parse first line for session_meta
        guard let firstLineData = lines[0].data(using: .utf8) else { return nil }

        let metaEntry: CodexSessionMetaEntry
        do {
            metaEntry = try decoder.decode(CodexSessionMetaEntry.self, from: firstLineData)
        } catch {
            return nil
        }

        guard metaEntry.type == "session_meta",
            let payload = metaEntry.payload
        else { return nil }

        // Check if cwd matches repository path
        let sessionCwd = payload.cwd
        guard sessionCwd == repositoryPath || sessionCwd.hasPrefix(repositoryPath + "/") else {
            return nil
        }

        // Get file modification date
        let modDate =
            (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

        // Parse timestamp for creation date
        let createdAt = ISO8601DateFormatter().date(from: payload.timestamp) ?? modDate

        // Find first user message for summary and count messages
        var firstPrompt = ""
        var messageCount = 0

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8) else { continue }

            do {
                let entry = try decoder.decode(CodexEventMsg.self, from: lineData)

                // Only count event_msg entries with user_message or agent_message
                guard entry.type == "event_msg",
                    let eventPayload = entry.payload,
                    let messageType = eventPayload.type,
                    let messageText = eventPayload.message,
                    !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }

                if messageType == "user_message" || messageType == "agent_message" {
                    messageCount += 1

                    // Use first user message as the summary
                    if firstPrompt.isEmpty && messageType == "user_message" {
                        firstPrompt = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } catch {
                continue
            }
        }

        // Skip sessions with no messages
        guard messageCount > 0 else { return nil }

        return CodexSessionEntry(
            sessionId: payload.id,
            firstPrompt: firstPrompt,
            messageCount: messageCount,
            createdAt: createdAt,
            lastModified: modDate,
            cwd: sessionCwd,
            filePath: fileURL.path
        )
    }
}
