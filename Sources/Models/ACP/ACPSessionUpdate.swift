//
//  ACPSessionUpdate.swift
//  agentmonitor
//
//  Agent Client Protocol - Session Update Notification Types
//

import Foundation

// MARK: - Session Update

struct SessionUpdate: Codable, Sendable {
    let sessionId: SessionId
    let update: SessionUpdateType

    enum CodingKeys: String, CodingKey {
        case sessionId
        case update
    }
}

// MARK: - Session Update Type

enum SessionUpdateType: Codable, Sendable {
    case agentMessageChunk(AgentMessageChunk)
    case agentThoughtChunk(AgentThoughtChunk)
    case toolCall(ToolCallUpdate)
    case toolCallUpdate(ToolCallProgressUpdate)
    case plan(PlanUpdate)
    case availableCommands(AvailableCommandsUpdate)
    case configOptions(ConfigOptionsUpdate)
    case unknown(String)

    enum CodingKeys: String, CodingKey {
        case sessionUpdate  // The actual field name from the protocol
        case content
        case text
        case toolCallId, title, kind, status, locations
        case rawInput, rawOutput
        case entries
        case commands, availableCommands
        case configOptions
        case parentToolCallId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .sessionUpdate)

        switch type {
        case "agent_message_chunk":
            self = .agentMessageChunk(try AgentMessageChunk(from: decoder))
        case "agent_thought_chunk":
            self = .agentThoughtChunk(try AgentThoughtChunk(from: decoder))
        case "tool_call":
            self = .toolCall(try ToolCallUpdate(from: decoder))
        case "tool_call_update":
            self = .toolCallUpdate(try ToolCallProgressUpdate(from: decoder))
        case "plan":
            self = .plan(try PlanUpdate(from: decoder))
        case "available_commands_update":
            self = .availableCommands(try AvailableCommandsUpdate(from: decoder))
        case "config_options_update":
            self = .configOptions(try ConfigOptionsUpdate(from: decoder))
        default:
            self = .unknown(type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .agentMessageChunk(let chunk):
            try container.encode("agent_message_chunk", forKey: .sessionUpdate)
            try chunk.encode(to: encoder)
        case .agentThoughtChunk(let chunk):
            try container.encode("agent_thought_chunk", forKey: .sessionUpdate)
            try chunk.encode(to: encoder)
        case .toolCall(let update):
            try container.encode("tool_call", forKey: .sessionUpdate)
            try update.encode(to: encoder)
        case .toolCallUpdate(let update):
            try container.encode("tool_call_update", forKey: .sessionUpdate)
            try update.encode(to: encoder)
        case .plan(let update):
            try container.encode("plan", forKey: .sessionUpdate)
            try update.encode(to: encoder)
        case .availableCommands(let update):
            try container.encode("available_commands_update", forKey: .sessionUpdate)
            try update.encode(to: encoder)
        case .configOptions(let update):
            try container.encode("config_options_update", forKey: .sessionUpdate)
            try update.encode(to: encoder)
        case .unknown(let type):
            try container.encode(type, forKey: .sessionUpdate)
        }
    }
}

// MARK: - Update Types

struct AgentMessageChunk: Codable, Sendable {
    let text: String

    enum CodingKeys: String, CodingKey {
        case content
    }

    private enum ContentKeys: String, CodingKey {
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let contentContainer = try container.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
        text = try contentContainer.decode(String.self, forKey: .text)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var contentContainer = container.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
        try contentContainer.encode(text, forKey: .text)
    }
}

struct AgentThoughtChunk: Codable, Sendable {
    let text: String

    enum CodingKeys: String, CodingKey {
        case content
    }

    private enum ContentKeys: String, CodingKey {
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let contentContainer = try container.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
        text = try contentContainer.decode(String.self, forKey: .text)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var contentContainer = container.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
        try contentContainer.encode(text, forKey: .text)
    }
}

struct ToolCallUpdate: Codable, Sendable {
    let toolCallId: String
    let title: String
    let kind: ToolKind?
    let status: ToolStatus
    let content: [ToolCallContent]?
    let locations: [ToolLocation]?
    let rawInput: AnyCodable?
    let rawOutput: AnyCodable?
    let parentToolCallId: String?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case title
        case kind
        case status
        case content
        case locations
        case rawInput
        case rawOutput
        case parentToolCallId
    }
}

struct ToolCallProgressUpdate: Codable, Sendable {
    let toolCallId: String
    let title: String?
    let status: ToolStatus?
    let content: [ToolCallContent]?
    let locations: [ToolLocation]?
    let rawInput: AnyCodable?
    let rawOutput: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case title
        case status
        case content
        case locations
        case rawInput
        case rawOutput
    }
}

struct PlanUpdate: Codable, Sendable {
    let entries: [PlanEntry]

    enum CodingKeys: String, CodingKey {
        case entries
    }
}

struct AvailableCommandsUpdate: Codable, Sendable {
    let commands: [AvailableCommand]

    enum CodingKeys: String, CodingKey {
        case commands = "availableCommands"
    }
}

struct ConfigOptionsUpdate: Codable, Sendable {
    let configOptions: [SessionConfigOption]

    enum CodingKeys: String, CodingKey {
        case configOptions
    }
}
