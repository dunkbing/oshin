//
//  ConversationStore.swift
//  oshin
//
//  Persistent storage for chat conversation history
//

import Foundation
import os.log

// MARK: - Stored Conversation

struct StoredConversation: Codable, Identifiable {
    let id: UUID
    let repositoryPath: String
    let agentId: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [MessageItem]

    init(
        id: UUID = UUID(),
        repositoryPath: String,
        agentId: String,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [MessageItem] = []
    ) {
        self.id = id
        self.repositoryPath = repositoryPath
        self.agentId = agentId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

// MARK: - Conversation Store

@MainActor
class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.oshin",
        category: "ConversationStore"
    )

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Base directory for storing conversations
    private var conversationsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.oshin"
        return appSupport.appendingPathComponent(bundleId).appendingPathComponent("conversations")
    }

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Ensure conversations directory exists
        try? fileManager.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Load all conversations for a specific repository and agent
    func loadConversations(repositoryPath: String, agentId: String) -> [StoredConversation] {
        let repoDir = directoryForRepository(repositoryPath)
        guard fileManager.fileExists(atPath: repoDir.path) else {
            return []
        }

        do {
            let files = try fileManager.contentsOfDirectory(at: repoDir, includingPropertiesForKeys: nil)
            let conversations = files.compactMap { url -> StoredConversation? in
                guard url.pathExtension == "json" else { return nil }
                return loadConversation(from: url)
            }
            .filter { $0.agentId == agentId }
            .sorted { $0.updatedAt > $1.updatedAt }

            print("Loaded \(conversations.count) conversations for \(agentId) in \(repositoryPath)")
            return conversations
        } catch {
            logger.error("Failed to load conversations: \(error.localizedDescription)")
            return []
        }
    }

    /// Load all conversations for a repository (all agents)
    func loadAllConversations(repositoryPath: String) -> [StoredConversation] {
        let repoDir = directoryForRepository(repositoryPath)
        guard fileManager.fileExists(atPath: repoDir.path) else {
            return []
        }

        do {
            let files = try fileManager.contentsOfDirectory(at: repoDir, includingPropertiesForKeys: nil)
            let conversations = files.compactMap { url -> StoredConversation? in
                guard url.pathExtension == "json" else { return nil }
                return loadConversation(from: url)
            }
            .sorted { $0.updatedAt > $1.updatedAt }

            return conversations
        } catch {
            logger.error("Failed to load conversations: \(error.localizedDescription)")
            return []
        }
    }

    /// Save a conversation
    func saveConversation(_ conversation: StoredConversation) {
        let repoDir = directoryForRepository(conversation.repositoryPath)

        // Ensure directory exists
        try? fileManager.createDirectory(at: repoDir, withIntermediateDirectories: true)

        let fileURL = repoDir.appendingPathComponent("\(conversation.id.uuidString).json")

        do {
            let data = try encoder.encode(conversation)
            try data.write(to: fileURL, options: .atomic)
            logger.debug("Saved conversation \(conversation.id) to \(fileURL.path)")
        } catch {
            logger.error("Failed to save conversation: \(error.localizedDescription)")
        }
    }

    /// Delete a conversation
    func deleteConversation(_ conversation: StoredConversation) {
        let repoDir = directoryForRepository(conversation.repositoryPath)
        let fileURL = repoDir.appendingPathComponent("\(conversation.id.uuidString).json")

        do {
            try fileManager.removeItem(at: fileURL)
            print("Deleted conversation \(conversation.id)")
        } catch {
            logger.error("Failed to delete conversation: \(error.localizedDescription)")
        }
    }

    /// Delete a conversation by ID and repository path
    func deleteConversation(id: UUID, repositoryPath: String) {
        let repoDir = directoryForRepository(repositoryPath)
        let fileURL = repoDir.appendingPathComponent("\(id.uuidString).json")

        do {
            try fileManager.removeItem(at: fileURL)
            print("Deleted conversation \(id)")
        } catch {
            logger.error("Failed to delete conversation: \(error.localizedDescription)")
        }
    }

    /// Get a specific conversation by ID
    func getConversation(id: UUID, repositoryPath: String) -> StoredConversation? {
        let repoDir = directoryForRepository(repositoryPath)
        let fileURL = repoDir.appendingPathComponent("\(id.uuidString).json")
        return loadConversation(from: fileURL)
    }

    // MARK: - Private Helpers

    private func directoryForRepository(_ repositoryPath: String) -> URL {
        // Create a safe directory name from the repository path
        let safeName =
            repositoryPath
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        // Use hash for uniqueness in case of collisions
        let hash = String(repositoryPath.hashValue, radix: 16, uppercase: false)
        let dirName = "\(safeName.prefix(50))_\(hash)"

        return conversationsDirectory.appendingPathComponent(dirName)
    }

    private func loadConversation(from url: URL) -> StoredConversation? {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(StoredConversation.self, from: data)
        } catch {
            logger.error("Failed to load conversation from \(url.path): \(error.localizedDescription)")
            return nil
        }
    }
}
