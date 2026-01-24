//
//  TerminalSession.swift
//  agentmonitor
//
//  In-memory terminal session model
//

import Foundation

@MainActor
class TerminalSession: ObservableObject, Identifiable {
    let id: UUID
    let repositoryPath: String
    @Published var title: String
    @Published var isActive: Bool = true
    let createdAt: Date

    init(repositoryPath: String, title: String? = nil) {
        self.id = UUID()
        self.repositoryPath = repositoryPath
        self.title = title ?? "Terminal"
        self.createdAt = Date()
    }
}
