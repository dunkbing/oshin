//
//  AgentInstaller.swift
//  agentmonitor
//
//  Agent installation manager coordinator for ACP agents
//

import Foundation
import os.log

// MARK: - Installation State

@MainActor
class AgentInstallState: ObservableObject {
    static let shared = AgentInstallState()

    @Published private(set) var installingAgents: Set<String> = []
    @Published private(set) var installErrors: [String: String] = [:]

    func setInstalling(_ agentId: String, _ isInstalling: Bool) {
        if isInstalling {
            installingAgents.insert(agentId)
            installErrors.removeValue(forKey: agentId)
        } else {
            installingAgents.remove(agentId)
        }
    }

    func setError(_ agentId: String, _ error: String?) {
        if let error {
            installErrors[agentId] = error
        } else {
            installErrors.removeValue(forKey: agentId)
        }
    }

    func isInstalling(_ agentId: String) -> Bool {
        installingAgents.contains(agentId)
    }

    func getError(_ agentId: String) -> String? {
        installErrors[agentId]
    }
}

// MARK: - Install Error

enum AgentInstallError: LocalizedError {
    case downloadFailed(message: String)
    case installFailed(message: String)
    case unsupportedPlatform
    case invalidResponse
    case fileSystemError(message: String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .installFailed(let message):
            return "Installation failed: \(message)"
        case .unsupportedPlatform:
            return "Unsupported platform"
        case .invalidResponse:
            return "Invalid server response"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        }
    }
}

actor AgentInstaller {
    static let shared = AgentInstaller()

    private let baseInstallPath: String
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.agentmonitor",
        category: "AgentInstaller"
    )

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        baseInstallPath = homeDir.appendingPathComponent(".agentmonitor/agents").path
    }

    // MARK: - Installation Status

    func canInstall(_ metadata: AgentMetadata) -> Bool {
        return metadata.installMethod != nil
    }

    func isInstalled(_ agentName: String) -> Bool {
        let agentPath = getAgentExecutablePath(agentName)
        return FileManager.default.fileExists(atPath: agentPath)
            && FileManager.default.isExecutableFile(atPath: agentPath)
    }

    func canUpdate(_ metadata: AgentMetadata) -> Bool {
        guard metadata.installMethod != nil else { return false }

        let managedPath = getAgentExecutablePath(metadata.id)
        guard !managedPath.isEmpty else { return false }

        guard let actualPath = metadata.executablePath else { return false }

        return actualPath == managedPath && FileManager.default.fileExists(atPath: managedPath)
    }

    func getAgentExecutablePath(_ agentName: String) -> String {
        let agentDir = (baseInstallPath as NSString).appendingPathComponent(agentName)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        switch agentName {
        case "claude":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/claude-code-acp")
        case "codex":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/codex-acp")
        case "droid":
            return (homeDir as NSString).appendingPathComponent(".local/bin/droid")
        case "gemini":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/gemini")
        case "kimi":
            return (agentDir as NSString).appendingPathComponent("kimi")
        case "opencode":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/opencode")
        case "vibe":
            return (agentDir as NSString).appendingPathComponent("vibe-acp")
        case "qwen":
            return (agentDir as NSString).appendingPathComponent("node_modules/.bin/qwen")
        default:
            return ""
        }
    }

    // MARK: - Installation

    func installAgent(_ metadata: AgentMetadata) async throws {
        print("installAgent called for: \(metadata.id) (\(metadata.name))")

        guard let installMethod = metadata.installMethod else {
            print("No install method for agent: \(metadata.id)")
            throw AgentInstallError.installFailed(
                message: "Agent '\(metadata.name)' has no installation method")
        }

        let agentDir = (baseInstallPath as NSString).appendingPathComponent(metadata.id)
        print("Agent install directory: \(agentDir)")

        try createDirectoryIfNeeded(agentDir)
        print("Directory created/verified")

        switch installMethod {
        case .npm(let package):
            print("Installing via NPM: \(package)")
            try await NPMAgentInstaller.shared.install(
                package: package,
                targetDir: agentDir
            )
        case .uv(let package):
            print("Installing via UV: \(package)")
            try await UVAgentInstaller.shared.install(
                package: package,
                targetDir: agentDir,
                executableName: metadata.id
            )
        case .binary(let urlString):
            let arch = getArchitecture()
            let resolvedURL = urlString.replacingOccurrences(of: "{arch}", with: arch)
            print("Installing binary from: \(resolvedURL)")
            try await BinaryAgentInstaller.shared.install(
                from: resolvedURL,
                agentId: metadata.id,
                targetDir: agentDir
            )
        case .githubRelease(let repo, let assetPattern):
            print("Installing from GitHub release: \(repo) pattern: \(assetPattern)")
            try await GitHubReleaseInstaller.shared.install(
                repo: repo,
                assetPattern: assetPattern,
                agentId: metadata.id,
                targetDir: agentDir
            )
        case .script(let urlString):
            print("Installing via script: \(urlString)")
            try await ScriptAgentInstaller.shared.install(from: urlString)
        }

        let executablePath = getAgentExecutablePath(metadata.id)
        print("Setting executable path: \(executablePath)")
        await AgentRegistry.shared.setAgentPath(executablePath, for: metadata.id)
        print("Installation complete for: \(metadata.id)")
    }

    func installAgent(_ agentName: String) async throws {
        let metadata = await AgentRegistry.shared.getMetadata(for: agentName)
        guard let metadata = metadata else {
            throw AgentInstallError.installFailed(message: "Unknown agent: \(agentName)")
        }

        try await installAgent(metadata)
    }

    // MARK: - Update

    func updateAgent(_ metadata: AgentMetadata) async throws {
        guard canUpdate(metadata) else {
            throw AgentInstallError.installFailed(message: "Agent '\(metadata.name)' cannot be updated")
        }

        let agentDir = (baseInstallPath as NSString).appendingPathComponent(metadata.id)
        if FileManager.default.fileExists(atPath: agentDir) {
            try FileManager.default.removeItem(atPath: agentDir)
        }

        try await installAgent(metadata)
    }

    // MARK: - Uninstallation

    func uninstallAgent(_ agentName: String) async throws {
        let agentDir = (baseInstallPath as NSString).appendingPathComponent(agentName)

        if FileManager.default.fileExists(atPath: agentDir) {
            try FileManager.default.removeItem(atPath: agentDir)
        }

        await AgentRegistry.shared.removeAgent(named: agentName)
    }

    // MARK: - Helpers

    private func createDirectoryIfNeeded(_ path: String) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            try fileManager.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    private func getArchitecture() -> String {
        #if arch(arm64)
            return "aarch64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "unknown"
        #endif
    }
}
