//
//  ChatSession.swift
//  agentmonitor
//
//  In-memory chat session model
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

    init(repositoryPath: String, agentId: String, title: String? = nil) {
        self.id = UUID()
        self.repositoryPath = repositoryPath
        self.agentId = agentId
        self.title = title ?? AgentRegistry.shared.getMetadata(for: agentId)?.name ?? agentId
        self.createdAt = Date()
    }
}
