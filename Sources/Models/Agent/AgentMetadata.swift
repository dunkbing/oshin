//
//  AgentMetadata.swift
//  oshin
//
//  Agent configuration metadata
//

import Foundation

struct AgentMetadata: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var description: String?
    var iconType: AgentIconType
    var isBuiltIn: Bool
    var isEnabled: Bool
    var executablePath: String?
    var launchArgs: [String]
    var installMethod: AgentInstallMethod?

    var canEditPath: Bool {
        !isBuiltIn
    }

    init(
        id: String,
        name: String,
        description: String? = nil,
        iconType: AgentIconType,
        isBuiltIn: Bool,
        isEnabled: Bool = true,
        executablePath: String? = nil,
        launchArgs: [String] = [],
        installMethod: AgentInstallMethod? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconType = iconType
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.executablePath = executablePath
        self.launchArgs = launchArgs
        self.installMethod = installMethod
    }
}
