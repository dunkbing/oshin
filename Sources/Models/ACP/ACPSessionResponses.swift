//
//  ACPSessionResponses.swift
//  oshin
//
//  Agent Client Protocol - Response Types
//

import Foundation

// MARK: - Initialize

struct InitializeResponse: Codable, Sendable {
    let protocolVersion: Int
    let agentInfo: AgentInfo?
    let agentCapabilities: AgentCapabilities
    let authMethods: [AuthMethod]?

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case agentInfo
        case agentCapabilities
        case authMethods
    }
}

// MARK: - Session Management

struct NewSessionResponse: Codable, Sendable {
    let sessionId: SessionId
    let modes: ModesInfo?
    let models: ModelsInfo?
    let configOptions: [SessionConfigOption]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modes
        case models
        case configOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(SessionId.self, forKey: .sessionId)
        // Gracefully handle modes/models that might have unexpected structure
        modes = try? container.decodeIfPresent(ModesInfo.self, forKey: .modes)
        models = try? container.decodeIfPresent(ModelsInfo.self, forKey: .models)
        configOptions = try? container.decodeIfPresent([SessionConfigOption].self, forKey: .configOptions)
    }
}

struct LoadSessionResponse: Codable, Sendable {
    let sessionId: SessionId

    enum CodingKeys: String, CodingKey {
        case sessionId
    }
}

// MARK: - Prompt

struct SessionPromptResponse: Codable, Sendable {
    let stopReason: StopReason

    enum CodingKeys: String, CodingKey {
        case stopReason
    }
}

// MARK: - Mode & Model Selection

struct SetModeResponse: Codable, Sendable {
    let success: Bool
}

struct SetModelResponse: Codable, Sendable {
    let success: Bool
}

struct SetSessionConfigOptionResponse: Codable, Sendable {
    let configOptions: [SessionConfigOption]

    enum CodingKeys: String, CodingKey {
        case configOptions
    }
}

// MARK: - Authentication

struct AuthenticateResponse: Codable, Sendable {
    let success: Bool
    let error: String?
}

// MARK: - File System

struct ReadTextFileResponse: Codable, Sendable {
    let content: String
    let totalLines: Int?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case content
        case totalLines = "total_lines"
        case _meta
    }
}

struct WriteTextFileResponse: Codable, Sendable {
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case _meta
    }
}
