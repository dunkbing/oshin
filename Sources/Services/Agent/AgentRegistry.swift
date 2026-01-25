//
//  AgentRegistry.swift
//  agentmonitor
//
//  Agent configuration registry
//

import Foundation

extension Notification.Name {
    static let agentMetadataDidChange = Notification.Name("agentMetadataDidChange")
}

@MainActor
class AgentRegistry: ObservableObject {
    static let shared = AgentRegistry()

    @Published private(set) var agentMetadata: [String: AgentMetadata] = [:]

    private let userDefaults = UserDefaults.standard
    private let metadataKey = "agentMetadata"
    private let authPreferencesKey = "agentAuthPreferences"

    static let builtInExecutableNames: [String: String] = [
        "claude": "claude-code-acp",
        "codex": "codex-acp",
        "gemini": "gemini",
        "droid": "droid",
        "kimi": "kimi",
        "opencode": "opencode",
        "vibe": "vibe-acp",
        "qwen": "qwen",
    ]

    static let managedAgentsBasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.agentmonitor/agents"
    }()

    private init() {
        loadMetadata()
        initializeDefaultAgents()
    }

    // MARK: - Agent Access

    func getAllAgents() -> [AgentMetadata] {
        return Array(agentMetadata.values).sorted { $0.name < $1.name }
    }

    func getEnabledAgents() -> [AgentMetadata] {
        return getAllAgents().filter { $0.isEnabled }
    }

    func getMetadata(for agentId: String) -> AgentMetadata? {
        return agentMetadata[agentId]
    }

    func getAgentPath(for agentId: String) -> String? {
        return agentMetadata[agentId]?.executablePath
    }

    func validateAgent(named agentId: String) -> Bool {
        guard let path = getAgentPath(for: agentId) else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    // MARK: - Agent Management

    func updateAgent(_ metadata: AgentMetadata) async {
        agentMetadata[metadata.id] = metadata
        saveMetadata()
        NotificationCenter.default.post(name: .agentMetadataDidChange, object: nil)
    }

    func setAgentPath(_ path: String, for agentId: String) async {
        guard var metadata = agentMetadata[agentId] else { return }
        metadata.executablePath = path
        agentMetadata[agentId] = metadata
        saveMetadata()
    }

    func addCustomAgent(_ metadata: AgentMetadata) async {
        agentMetadata[metadata.id] = metadata
        saveMetadata()
        NotificationCenter.default.post(name: .agentMetadataDidChange, object: nil)
    }

    func deleteAgent(id: String) async {
        agentMetadata.removeValue(forKey: id)
        saveMetadata()
        NotificationCenter.default.post(name: .agentMetadataDidChange, object: nil)
    }

    func removeAgent(named agentId: String) async {
        agentMetadata.removeValue(forKey: agentId)
        saveMetadata()
    }

    // MARK: - Authentication Preferences

    func saveAuthPreference(agentId: String, methodId: String) async {
        var prefs = getAuthPreferences()
        prefs[agentId] = methodId
        userDefaults.set(prefs, forKey: authPreferencesKey)
    }

    func getAuthMethodId(for agentId: String) -> String? {
        return getAuthPreferences()[agentId]
    }

    func getAuthMethodName(for agentId: String) -> String? {
        return getAuthPreferences()[agentId]
    }

    func clearAuthPreference(for agentId: String) {
        var prefs = getAuthPreferences()
        prefs.removeValue(forKey: agentId)
        userDefaults.set(prefs, forKey: authPreferencesKey)
    }

    private func getAuthPreferences() -> [String: String] {
        return userDefaults.dictionary(forKey: authPreferencesKey) as? [String: String] ?? [:]
    }

    // MARK: - Persistence

    private func loadMetadata() {
        guard let data = userDefaults.data(forKey: metadataKey),
            let decoded = try? JSONDecoder().decode([String: AgentMetadata].self, from: data)
        else {
            return
        }
        agentMetadata = decoded
    }

    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(agentMetadata) else { return }
        userDefaults.set(data, forKey: metadataKey)
    }

    // MARK: - Default Agents

    static func managedPath(for agentId: String) -> String {
        let basePath = managedAgentsBasePath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch agentId {
        case "claude":
            return "\(basePath)/claude/node_modules/.bin/claude-code-acp"
        case "codex":
            return "\(basePath)/codex/node_modules/.bin/codex-acp"
        case "droid":
            return "\(home)/.local/bin/droid"
        case "gemini":
            return "\(basePath)/gemini/node_modules/.bin/gemini"
        case "kimi":
            return "\(basePath)/kimi/kimi"
        case "opencode":
            return "\(basePath)/opencode/node_modules/.bin/opencode"
        case "vibe":
            return "\(basePath)/vibe/vibe-acp"
        case "qwen":
            return "\(basePath)/qwen/node_modules/.bin/qwen"
        default:
            return "\(basePath)/\(agentId)/\(agentId)"
        }
    }

    static func isInstalledAtManagedPath(_ agentId: String) -> Bool {
        let path = managedPath(for: agentId)
        return FileManager.default.isExecutableFile(atPath: path)
    }

    func initializeDefaultAgents() {
        var metadata = agentMetadata

        metadata = metadata.filter { id, agent in
            if !agent.isBuiltIn {
                return true
            }
            return Self.builtInExecutableNames.keys.contains(id)
        }

        updateBuiltInAgent("claude", in: &metadata) {
            AgentMetadata(
                id: "claude",
                name: "Claude",
                description: "Agentic coding tool that understands your codebase",
                iconType: .builtin("claude"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "claude"),
                launchArgs: [],
                installMethod: .npm(package: "@zed-industries/claude-code-acp")
            )
        }

        updateBuiltInAgent("codex", in: &metadata) {
            AgentMetadata(
                id: "codex",
                name: "Codex",
                description: "Lightweight open-source coding agent by OpenAI",
                iconType: .builtin("openai"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "codex"),
                launchArgs: [],
                installMethod: .npm(package: "@zed-industries/codex-acp")
            )
        }

        updateBuiltInAgent("droid", in: &metadata) {
            AgentMetadata(
                id: "droid",
                name: "Droid",
                description: "Factory Droid agent for ACP-based coding sessions",
                iconType: .builtin("droid"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "droid"),
                launchArgs: ["exec", "--output-format", "acp"],
                installMethod: .script(url: "https://app.factory.ai/cli")
            )
        }

        updateBuiltInAgent("gemini", in: &metadata) {
            AgentMetadata(
                id: "gemini",
                name: "Gemini",
                description: "Open-source AI agent powered by Gemini models",
                iconType: .builtin("gemini"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "gemini"),
                launchArgs: ["--experimental-acp"],
                installMethod: .npm(package: "@google/gemini-cli")
            )
        }

        updateBuiltInAgent("kimi", in: &metadata) {
            AgentMetadata(
                id: "kimi",
                name: "Kimi",
                description: "CLI agent powered by Kimi K2, a trillion-parameter MoE model",
                iconType: .builtin("kimi"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "kimi"),
                launchArgs: ["--acp"],
                installMethod: .uv(package: "kimi-cli")
            )
        }

        updateBuiltInAgent("opencode", in: &metadata) {
            AgentMetadata(
                id: "opencode",
                name: "OpenCode",
                description: "Open-source coding agent with multi-session and LSP support",
                iconType: .builtin("opencode"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "opencode"),
                launchArgs: ["acp"],
                installMethod: .npm(package: "opencode-ai@latest")
            )
        }

        updateBuiltInAgent("vibe", in: &metadata) {
            AgentMetadata(
                id: "vibe",
                name: "Vibe",
                description: "Open-source coding assistant powered by Devstral",
                iconType: .builtin("vibe"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "vibe"),
                launchArgs: [],
                installMethod: .uv(package: "mistral-vibe")
            )
        }

        updateBuiltInAgent("qwen", in: &metadata) {
            AgentMetadata(
                id: "qwen",
                name: "Qwen Code",
                description: "CLI tool for agentic coding, powered by Qwen3-Coder",
                iconType: .builtin("qwen"),
                isBuiltIn: true,
                isEnabled: true,
                executablePath: Self.managedPath(for: "qwen"),
                launchArgs: ["--experimental-acp"],
                installMethod: .npm(package: "@qwen-code/qwen-code")
            )
        }

        agentMetadata = metadata
        saveMetadata()
    }

    private func updateBuiltInAgent(
        _ id: String,
        in metadata: inout [String: AgentMetadata],
        factory: () -> AgentMetadata
    ) {
        let template = factory()
        if var existing = metadata[id] {
            existing.executablePath = template.executablePath
            existing.installMethod = template.installMethod
            existing.launchArgs = template.launchArgs
            metadata[id] = existing
        } else {
            metadata[id] = template
        }
    }
}
