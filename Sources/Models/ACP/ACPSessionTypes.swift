//
//  ACPSessionTypes.swift
//  agentmonitor
//
//  Agent Client Protocol - Session Types
//

import Foundation

// MARK: - Session ID

struct SessionId: Codable, Hashable, Sendable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Client Info

struct ClientInfo: Codable, Sendable {
    let name: String
    let version: String?

    enum CodingKeys: String, CodingKey {
        case name, version
    }
}

// MARK: - Agent Info

struct AgentInfo: Codable, Sendable {
    let name: String
    let version: String?

    enum CodingKeys: String, CodingKey {
        case name, version
    }
}

// MARK: - Auth Method

struct AuthMethod: Codable, Sendable {
    let methodId: String
    let name: String
    let description: String?
    let credentialFields: [CredentialField]?

    enum CodingKeys: String, CodingKey {
        case methodId = "id"
        case name
        case description
        case credentialFields
    }
}

struct CredentialField: Codable, Sendable {
    let name: String
    let label: String
    let isSecret: Bool?

    enum CodingKeys: String, CodingKey {
        case name, label, isSecret
    }
}

// MARK: - Modes & Models (Legacy API)

struct ModesInfo: Codable, Sendable {
    let availableModes: [ModeInfo]
    let currentModeId: String

    enum CodingKeys: String, CodingKey {
        case availableModes
        case currentModeId
    }
}

struct ModeInfo: Codable, Identifiable, Sendable {
    let modeId: String
    let name: String
    let description: String?

    var id: String { modeId }

    enum CodingKeys: String, CodingKey {
        case modeId = "id"
        case name
        case description
    }
}

struct ModelsInfo: Codable, Sendable {
    let availableModels: [ModelInfo]
    let currentModelId: String

    enum CodingKeys: String, CodingKey {
        case availableModels
        case currentModelId
    }
}

struct ModelInfo: Codable, Identifiable, Sendable {
    let modelId: String
    let name: String
    let description: String?

    var id: String { modelId }

    enum CodingKeys: String, CodingKey {
        case modelId = "id"
        case name
        case description
    }
}

// MARK: - Stop Reason

enum StopReason: String, Codable, Sendable {
    case endTurn = "end_turn"
    case cancelled
    case maxTokens = "max_tokens"
    case toolUse = "tool_use"
    case timeout
    case error
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = StopReason(rawValue: rawValue) ?? .unknown
    }
}

// MARK: - MCP Server Config

struct MCPServerConfig: Codable, Sendable {
    let name: String
    let transport: MCPTransport

    enum CodingKeys: String, CodingKey {
        case name, transport
    }
}

enum MCPTransport: Codable, Sendable {
    case stdio(MCPStdioTransport)
    case http(MCPHttpTransport)
    case sse(MCPSseTransport)

    enum CodingKeys: String, CodingKey {
        case type, command, args, env, url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "stdio":
            self = .stdio(try MCPStdioTransport(from: decoder))
        case "http":
            self = .http(try MCPHttpTransport(from: decoder))
        case "sse":
            self = .sse(try MCPSseTransport(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown transport type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .stdio(let transport):
            try transport.encode(to: encoder)
        case .http(let transport):
            try transport.encode(to: encoder)
        case .sse(let transport):
            try transport.encode(to: encoder)
        }
    }
}

struct MCPStdioTransport: Codable, Sendable {
    let type: String = "stdio"
    let command: String
    let args: [String]?
    let env: [String: String]?

    enum CodingKeys: String, CodingKey {
        case type, command, args, env
    }
}

struct MCPHttpTransport: Codable, Sendable {
    let type: String = "http"
    let url: String

    enum CodingKeys: String, CodingKey {
        case type, url
    }
}

struct MCPSseTransport: Codable, Sendable {
    let type: String = "sse"
    let url: String

    enum CodingKeys: String, CodingKey {
        case type, url
    }
}
