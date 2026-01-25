//
//  ACPTerminalTypes.swift
//  agentmonitor
//
//  Agent Client Protocol - Terminal Types
//

import Foundation

// MARK: - Terminal Types

struct TerminalId: Codable, Hashable, Sendable {
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

// MARK: - Environment Variable

struct EnvVariable: Codable, Sendable {
    let name: String
    let value: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, value, _meta
    }
}

// MARK: - Terminal Exit Status

struct TerminalExitStatus: Codable, Sendable {
    let exitCode: Int?
    let signal: String?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case exitCode
        case signal
        case _meta
    }
}

// MARK: - Create Terminal

struct CreateTerminalRequest: Codable, Sendable {
    let command: String
    let args: [String]?
    let cwd: String?
    let env: [EnvVariable]?
    let outputByteLimit: Int?
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case command, args, cwd, env, sessionId
        case outputByteLimit = "outputByteLimit"
        case _meta
    }
}

struct CreateTerminalResponse: Codable, Sendable {
    let terminalId: TerminalId
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case _meta
    }
}

// MARK: - Terminal Output

struct TerminalOutputRequest: Codable, Sendable {
    let terminalId: TerminalId
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }
}

struct TerminalOutputResponse: Codable, Sendable {
    let output: String
    let exitStatus: TerminalExitStatus?
    let truncated: Bool
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case output, truncated, exitStatus
        case _meta
    }
}

// MARK: - Wait for Exit

struct WaitForExitRequest: Codable, Sendable {
    let terminalId: TerminalId
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }
}

struct WaitForExitResponse: Codable, Sendable {
    let exitCode: Int?
    let signal: String?
    let _meta: [String: AnyCodable]?
}

// MARK: - Kill Terminal

struct KillTerminalRequest: Codable, Sendable {
    let terminalId: TerminalId
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }
}

struct KillTerminalResponse: Codable, Sendable {
    let success: Bool
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case success, _meta
    }
}

// MARK: - Release Terminal

struct ReleaseTerminalRequest: Codable, Sendable {
    let terminalId: TerminalId
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }
}

struct ReleaseTerminalResponse: Codable, Sendable {
    let success: Bool
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case success, _meta
    }
}
