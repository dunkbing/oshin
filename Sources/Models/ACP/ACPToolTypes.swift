//
//  ACPToolTypes.swift
//  oshin
//
//  Agent Client Protocol - Tool Call Types
//

import Foundation

// MARK: - Tool Call Content

enum ToolCallContent: Codable, Sendable {
    case content(ContentBlock)
    case diff(ToolCallDiff)
    case terminal(ToolCallTerminal)

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case path, oldText, newText
        case terminalId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "content":
            let block = try container.decode(ContentBlock.self, forKey: .content)
            self = .content(block)
        case "diff":
            let diff = try ToolCallDiff(from: decoder)
            self = .diff(diff)
        case "terminal":
            let terminal = try ToolCallTerminal(from: decoder)
            self = .terminal(terminal)
        default:
            if let text = try? container.decodeIfPresent(String.self, forKey: .content) {
                self = .content(.text(TextContent(text: text)))
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown tool call content type: \(type)"
                )
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .content(let block):
            try container.encode("content", forKey: .type)
            try container.encode(block, forKey: .content)
        case .diff(let diff):
            try container.encode("diff", forKey: .type)
            try diff.encode(to: encoder)
        case .terminal(let terminal):
            try container.encode("terminal", forKey: .type)
            try terminal.encode(to: encoder)
        }
    }

    var displayText: String? {
        switch self {
        case .content(let block):
            if case .text(let text) = block {
                return text.text
            }
            return nil
        case .diff(let diff):
            return "Modified: \(diff.path)"
        case .terminal(let terminal):
            return "Terminal: \(terminal.terminalId)"
        }
    }

    var asContentBlock: ContentBlock? {
        switch self {
        case .content(let block):
            return block
        case .diff(let diff):
            var text = "File: \(diff.path)\n"
            if let old = diff.oldText {
                text += "--- old\n\(old)\n"
            }
            text += "+++ new\n\(diff.newText)"
            return .text(TextContent(text: text))
        case .terminal:
            return nil
        }
    }
}

struct ToolCallDiff: Codable, Sendable {
    let path: String
    let oldText: String?
    let newText: String

    enum CodingKeys: String, CodingKey {
        case path, oldText, newText
    }
}

struct ToolCallTerminal: Codable, Sendable {
    let terminalId: String

    enum CodingKeys: String, CodingKey {
        case terminalId
    }
}

// MARK: - Tool Calls

struct ToolCall: Codable, Identifiable, Sendable {
    let toolCallId: String
    var title: String
    var kind: ToolKind?
    var status: ToolStatus
    var content: [ToolCallContent]
    var locations: [ToolLocation]?
    var rawInput: AnyCodable?
    var rawOutput: AnyCodable?
    var timestamp: Date = Date()
    var iterationId: String?
    var parentToolCallId: String?

    var id: String { toolCallId }

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case title, kind, status, content, locations
        case rawInput
        case rawOutput
    }

    var resolvedKind: ToolKind {
        kind ?? .other
    }

    var contentBlocks: [ContentBlock] {
        content.compactMap { $0.asContentBlock }
    }

    var copyableOutputText: String? {
        let outputs = content.compactMap { $0.copyableText }
        let result = outputs.joined(separator: "\n\n")
        return result.isEmpty ? nil : result
    }
}

extension ToolCallContent {
    fileprivate var copyableText: String? {
        switch self {
        case .content(let block):
            if case .text(let textContent) = block {
                return textContent.text
            }
            return nil
        case .diff(let diff):
            return diff.newText
        case .terminal:
            return nil
        }
    }
}

enum ToolKind: String, Codable, Sendable {
    case read
    case edit
    case delete
    case move
    case search
    case execute
    case think
    case fetch
    case switchMode = "switch_mode"
    case plan
    case exitPlanMode = "exit_plan_mode"
    case other

    var symbolName: String {
        switch self {
        case .read: return "doc.text"
        case .edit: return "pencil"
        case .delete: return "trash"
        case .move: return "arrow.right.doc.on.clipboard"
        case .search: return "magnifyingglass"
        case .execute: return "terminal"
        case .think: return "brain"
        case .fetch: return "arrow.down.circle"
        case .switchMode: return "arrow.left.arrow.right"
        case .plan: return "list.bullet.clipboard"
        case .exitPlanMode: return "checkmark.circle"
        case .other: return "wrench.and.screwdriver"
        }
    }
}

enum ToolStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
    case failed
}

struct ToolLocation: Codable, Sendable {
    let path: String?
    let line: Int?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, line, _meta
    }
}

// MARK: - Available Commands

struct AvailableCommand: Codable, Sendable {
    let name: String
    let description: String
    let input: CommandInputSpec?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, description, input, _meta
    }
}

struct CommandInputSpec: Codable, Sendable {
    let type: String?
    let hint: String?
    let properties: [String: AnyCodable]?
    let required: [String]?
}

// MARK: - Agent Plan

enum PlanPriority: String, Codable, Sendable {
    case low
    case medium
    case high
}

enum PlanEntryStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled
}

struct PlanEntry: Codable, Equatable, Sendable {
    let content: String
    let priority: PlanPriority
    let status: PlanEntryStatus
    let activeForm: String?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case content, priority, status, activeForm, _meta
    }

    static func == (lhs: PlanEntry, rhs: PlanEntry) -> Bool {
        lhs.content == rhs.content && lhs.priority == rhs.priority && lhs.status == rhs.status
            && lhs.activeForm == rhs.activeForm
    }
}

struct Plan: Codable, Equatable, Sendable {
    let entries: [PlanEntry]
}
