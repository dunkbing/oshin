//
//  ClaudeSessionParser.swift
//  oshin
//
//  Parses Claude Code's JSONL session files to extract messages
//

import Foundation

// MARK: - JSONL Entry Types

struct ClaudeJSONLEntry: Codable {
    let type: String
    let uuid: String?
    let parentUuid: String?
    let sessionId: String?
    let timestamp: String?
    let message: ClaudeMessage?
}

struct ClaudeMessage: Codable {
    let role: String
    let content: ClaudeMessageContent

    enum CodingKeys: String, CodingKey {
        case role, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)

        // Content can be a string or an array of content blocks
        if let stringContent = try? container.decode(String.self, forKey: .content) {
            content = .text(stringContent)
        } else if let arrayContent = try? container.decode([ClaudeContentBlock].self, forKey: .content) {
            content = .blocks(arrayContent)
        } else {
            content = .text("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        switch content {
        case .text(let text):
            try container.encode(text, forKey: .content)
        case .blocks(let blocks):
            try container.encode(blocks, forKey: .content)
        }
    }
}

enum ClaudeMessageContent: Codable {
    case text(String)
    case blocks([ClaudeContentBlock])

    var textContent: String {
        switch self {
        case .text(let text):
            return text
        case .blocks(let blocks):
            return blocks.compactMap { block -> String? in
                switch block.type {
                case "text":
                    return block.text
                case "thinking":
                    return nil  // Skip thinking blocks
                case "tool_use":
                    return nil  // Skip tool use blocks for now
                case "tool_result":
                    return nil  // Skip tool results
                default:
                    return nil
                }
            }.joined(separator: "\n")
        }
    }
}

struct ClaudeContentBlock: Codable {
    let type: String
    let text: String?
    let thinking: String?
    let id: String?
    let name: String?
    let input: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case type, text, thinking, id, name, input
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        thinking = try? container.decodeIfPresent(String.self, forKey: .thinking)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        input = try? container.decodeIfPresent(AnyCodable.self, forKey: .input)
    }
}

// MARK: - Parsed Message

struct ParsedClaudeMessage: Identifiable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    let toolCalls: [ParsedToolCall]
}

struct ParsedToolCall: Identifiable {
    let id: String
    let name: String
    let input: String
}

// MARK: - Session Parser

@MainActor
class ClaudeSessionParser {
    static let shared = ClaudeSessionParser()

    private let decoder = JSONDecoder()
    private let isoFormatter = ISO8601DateFormatter()

    private init() {
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    /// Parse a JSONL file and return messages
    func parseSession(filePath: String) -> [MessageItem] {
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("[ClaudeSessionParser] File not found: \(filePath)")
            return []
        }

        guard let data = FileManager.default.contents(atPath: filePath),
            let content = String(data: data, encoding: .utf8)
        else {
            print("[ClaudeSessionParser] Failed to read file: \(filePath)")
            return []
        }

        let lines = content.components(separatedBy: .newlines)
        var messages: [MessageItem] = []

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8) else { continue }

            do {
                let entry = try decoder.decode(ClaudeJSONLEntry.self, from: lineData)

                // Only process user and assistant messages
                guard entry.type == "user" || entry.type == "assistant",
                    let message = entry.message,
                    let uuid = entry.uuid
                else { continue }

                let timestamp = parseTimestamp(entry.timestamp)
                let role: MessageRole = message.role == "user" ? .user : .agent
                let textContent = message.content.textContent

                // Skip empty messages
                guard !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                // Extract tool calls if present
                var toolCalls: [ToolCall] = []
                if case .blocks(let blocks) = message.content {
                    for block in blocks where block.type == "tool_use" {
                        if let toolId = block.id, let toolName = block.name {
                            let toolCall = ToolCall(
                                toolCallId: toolId,
                                title: toolName,
                                kind: mapToolKind(toolName),
                                status: .completed,
                                content: [],
                                locations: nil,
                                rawInput: block.input,
                                rawOutput: nil
                            )
                            toolCalls.append(toolCall)
                        }
                    }
                }

                let messageItem = MessageItem(
                    id: uuid,
                    role: role,
                    content: textContent,
                    timestamp: timestamp,
                    toolCalls: toolCalls,
                    isComplete: true
                )
                messages.append(messageItem)

            } catch {
                // Skip malformed lines
                continue
            }
        }

        print("[ClaudeSessionParser] Parsed \(messages.count) messages from \(filePath)")
        return messages
    }

    private func parseTimestamp(_ timestamp: String?) -> Date {
        guard let ts = timestamp else { return Date() }
        return isoFormatter.date(from: ts) ?? Date()
    }

    private func mapToolKind(_ toolName: String) -> ToolKind {
        switch toolName.lowercased() {
        case "read", "read_file":
            return .read
        case "edit", "str_replace_editor", "write":
            return .edit
        case "bash", "execute", "run":
            return .execute
        case "search", "grep", "glob":
            return .search
        case "think":
            return .think
        case "web_fetch", "fetch":
            return .fetch
        default:
            return .other
        }
    }
}
