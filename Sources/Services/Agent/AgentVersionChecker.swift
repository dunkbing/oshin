//
//  AgentVersionChecker.swift
//  oshin
//
//  Service to check ACP agent versions and suggest updates
//

import Foundation
import os.log

struct AgentVersionInfo: Codable, Sendable {
    let current: String?
    let latest: String?
    let isOutdated: Bool
    let updateAvailable: Bool
}

actor AgentVersionChecker {
    static let shared = AgentVersionChecker()

    private var versionCache: [String: AgentVersionInfo] = [:]
    private var lastCheckTime: [String: Date] = [:]
    private let cacheExpiration: TimeInterval = 3600  // 1 hour
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.oshin", category: "AgentVersion")

    private let baseInstallPath: String

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        baseInstallPath = homeDir.appendingPathComponent(".oshin/agents").path
    }

    /// Check if an agent's version is outdated
    func checkVersion(for agentName: String) async -> AgentVersionInfo {
        // Check cache first
        if let cached = versionCache[agentName],
            let lastCheck = lastCheckTime[agentName],
            Date().timeIntervalSince(lastCheck) < cacheExpiration
        {
            return cached
        }

        let metadata = await AgentRegistry.shared.getMetadata(for: agentName)
        guard let installMethod = metadata?.installMethod else {
            return AgentVersionInfo(current: nil, latest: nil, isOutdated: false, updateAvailable: false)
        }

        let agentDir = (baseInstallPath as NSString).appendingPathComponent(agentName)
        let info: AgentVersionInfo

        switch installMethod {
        case .npm(let package):
            info = await checkNpmVersion(package: package, agentDir: agentDir)
        case .uv, .binary, .githubRelease, .script:
            // UV/Binary/GithubRelease/Script installs don't have version tracking yet
            info = AgentVersionInfo(current: nil, latest: nil, isOutdated: false, updateAvailable: false)
        }

        // Cache the result
        versionCache[agentName] = info
        lastCheckTime[agentName] = Date()

        return info
    }

    // MARK: - NPM Version Detection

    /// Check NPM package version using local package.json
    private func checkNpmVersion(package: String, agentDir: String) async -> AgentVersionInfo {
        // Get current version from local installation
        let currentVersion = await getCurrentNpmVersion(package: package, agentDir: agentDir)

        // Get latest version from npm registry
        let latestVersion = await getLatestNpmVersion(package: package)

        let isOutdated = compareVersions(current: currentVersion, latest: latestVersion)

        return AgentVersionInfo(
            current: currentVersion,
            latest: latestVersion,
            isOutdated: isOutdated,
            updateAvailable: isOutdated
        )
    }

    /// Get current installed NPM package version from local package.json
    private func getCurrentNpmVersion(package: String, agentDir: String) async -> String? {
        // First try .version manifest file (written at install time)
        if let version = readVersionManifest(agentDir: agentDir) {
            return version
        }

        // Fallback: read from local node_modules package.json
        let cleanPackage = stripVersionSpecifier(from: package)
        let packageJsonPath =
            (agentDir as NSString).appendingPathComponent("node_modules/\(cleanPackage)/package.json")

        guard let data = FileManager.default.contents(atPath: packageJsonPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = json["version"] as? String
        else {
            return nil
        }

        return version
    }

    /// Get latest NPM package version from registry
    private func getLatestNpmVersion(package: String) async -> String? {
        // Strip version specifiers like @latest before querying
        let cleanPackage = stripVersionSpecifier(from: package)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "view", cleanPackage, "version"]
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            if let version = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines),
                !version.isEmpty
            {
                return version
            }
        } catch {
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            logger.error("Failed to get latest npm version for \(cleanPackage): \(error)")
        }

        return nil
    }

    /// Strip version specifier from package name (e.g., "opencode-ai@latest" -> "opencode-ai")
    private func stripVersionSpecifier(from package: String) -> String {
        // Handle scoped packages: @scope/name@version -> @scope/name
        if package.hasPrefix("@") {
            if let slashIndex = package.firstIndex(of: "/") {
                let afterSlash = package[package.index(after: slashIndex)...]
                if let atIndex = afterSlash.firstIndex(of: "@") {
                    return String(package[..<atIndex])
                }
            }
            return package
        }

        // Simple package: name@version -> name
        if let atIndex = package.firstIndex(of: "@") {
            return String(package[..<atIndex])
        }

        return package
    }

    // MARK: - Helpers

    /// Read version from manifest file
    private func readVersionManifest(agentDir: String) -> String? {
        let manifestPath = (agentDir as NSString).appendingPathComponent(".version")
        guard let version = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
            return nil
        }
        return version.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compare semantic versions
    private func compareVersions(current: String?, latest: String?) -> Bool {
        guard let current = current, let latest = latest else {
            return false
        }

        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(currentParts.count, latestParts.count) {
            let currentPart = i < currentParts.count ? currentParts[i] : 0
            let latestPart = i < latestParts.count ? latestParts[i] : 0

            if latestPart > currentPart {
                return true  // Outdated
            } else if latestPart < currentPart {
                return false  // Newer than latest (dev version?)
            }
        }

        return false  // Same version
    }

    /// Clear cache for an agent
    func clearCache(for agentName: String) {
        versionCache.removeValue(forKey: agentName)
        lastCheckTime.removeValue(forKey: agentName)
    }
}
