//
//  AgentIconType.swift
//  agentmonitor
//
//  Icon type for agent display
//

import Foundation

enum AgentIconType: Codable, Equatable, Sendable {
    case builtin(String)
    case sfSymbol(String)
    case customImage(Data)

    enum CodingKeys: String, CodingKey {
        case type, value, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "builtin":
            let value = try container.decode(String.self, forKey: .value)
            self = .builtin(value)
        case "sfSymbol":
            let value = try container.decode(String.self, forKey: .value)
            self = .sfSymbol(value)
        case "customImage":
            let data = try container.decode(Data.self, forKey: .data)
            self = .customImage(data)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown icon type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .builtin(let value):
            try container.encode("builtin", forKey: .type)
            try container.encode(value, forKey: .value)
        case .sfSymbol(let value):
            try container.encode("sfSymbol", forKey: .type)
            try container.encode(value, forKey: .value)
        case .customImage(let data):
            try container.encode("customImage", forKey: .type)
            try container.encode(data, forKey: .data)
        }
    }
}
