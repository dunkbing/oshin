//
//  ACPSessionRequests.swift
//  oshin
//
//  Agent Client Protocol - Request Types
//

import Foundation

// MARK: - Initialize

struct InitializeRequest: Codable, Sendable {
    let protocolVersion: Int
    let clientCapabilities: ClientCapabilities
    let clientInfo: ClientInfo?

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case clientCapabilities
        case clientInfo
    }
}

// MARK: - Session Management

struct NewSessionRequest: Codable, Sendable {
    let cwd: String
    let mcpServers: [MCPServerConfig]

    enum CodingKeys: String, CodingKey {
        case cwd
        case mcpServers
    }
}

struct LoadSessionRequest: Codable, Sendable {
    let sessionId: SessionId
    let cwd: String?
    let mcpServers: [MCPServerConfig]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case cwd
        case mcpServers
    }
}

struct CancelSessionRequest: Codable, Sendable {
    let sessionId: SessionId

    enum CodingKeys: String, CodingKey {
        case sessionId
    }
}

// MARK: - Prompt

struct SessionPromptRequest: Codable, Sendable {
    let sessionId: SessionId
    let prompt: [ContentBlock]

    enum CodingKeys: String, CodingKey {
        case sessionId
        case prompt
    }
}

// MARK: - Mode & Model Selection

struct SetModeRequest: Codable, Sendable {
    let sessionId: SessionId
    let modeId: String

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modeId
    }
}

struct SetModelRequest: Codable, Sendable {
    let sessionId: SessionId
    let modelId: String

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modelId
    }
}

struct SetSessionConfigOptionRequest: Codable, Sendable {
    let sessionId: SessionId
    let configId: SessionConfigId
    let value: SessionConfigValueId

    enum CodingKeys: String, CodingKey {
        case sessionId
        case configId
        case value
    }
}

// MARK: - Authentication

struct AuthenticateRequest: Codable, Sendable {
    let methodId: String
    let credentials: [String: String]?

    enum CodingKeys: String, CodingKey {
        case methodId
        case credentials
    }
}

// MARK: - File System

struct ReadTextFileRequest: Codable, Sendable {
    let path: String
    let line: Int?
    let limit: Int?
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, line, limit, sessionId, _meta
    }
}

struct WriteTextFileRequest: Codable, Sendable {
    let path: String
    let content: String
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, content, sessionId, _meta
    }
}
