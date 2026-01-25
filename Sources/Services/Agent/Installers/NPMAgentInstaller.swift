//
//  NPMAgentInstaller.swift
//  agentmonitor
//
//  NPM package installation for ACP agents
//

import Foundation

actor NPMAgentInstaller {
    static let shared = NPMAgentInstaller()

    private let shellLoader: ShellEnvironmentLoader

    init(shellLoader: ShellEnvironmentLoader = .shared) {
        self.shellLoader = shellLoader
    }

    // MARK: - Installation

    func install(package: String, targetDir: String) async throws {
        print("NPM install starting for package: \(package)")
        print("Target directory: \(targetDir)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "install", "--prefix", targetDir, package]
        print("Running: npm install --prefix \(targetDir) \(package)")

        let shellEnv = await shellLoader.loadShellEnvironment()
        process.environment = shellEnv
        print("Shell environment loaded with PATH: \(shellEnv["PATH"] ?? "nil")")

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        print("Starting npm process...")
        try process.run()
        print("npm process started, waiting for exit...")
        process.waitUntilExit()
        print("npm process exited with status: \(process.terminationStatus)")

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
            print("npm stdout: \(output.prefix(500))")
        }
        if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
            print("npm stderr: \(errorOutput.prefix(500))")
        }

        try? pipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("npm install failed: \(errorMessage)")
            throw AgentInstallError.installFailed(message: errorMessage)
        }

        if let version = getInstalledVersion(package: package, targetDir: targetDir) {
            saveVersionManifest(version: version, targetDir: targetDir)
            print("Successfully installed \(package) version \(version)")
        } else {
            print("Could not determine installed version for \(package)")
        }
    }

    // MARK: - Version Detection

    func getInstalledVersion(package: String, targetDir: String) -> String? {
        let cleanPackage = stripVersionSpecifier(from: package)

        let packagePath =
            (targetDir as NSString).appendingPathComponent("node_modules/\(cleanPackage)/package.json")

        guard FileManager.default.fileExists(atPath: packagePath),
            let data = FileManager.default.contents(atPath: packagePath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = json["version"] as? String
        else {
            return nil
        }

        return version
    }

    private func stripVersionSpecifier(from package: String) -> String {
        if package.hasPrefix("@") {
            if let slashIndex = package.firstIndex(of: "/") {
                let afterSlash = package[package.index(after: slashIndex)...]
                if let atIndex = afterSlash.firstIndex(of: "@") {
                    return String(package[..<atIndex])
                }
            }
            return package
        }

        if let atIndex = package.firstIndex(of: "@") {
            return String(package[..<atIndex])
        }

        return package
    }

    private func saveVersionManifest(version: String, targetDir: String) {
        let manifestPath = (targetDir as NSString).appendingPathComponent(".version")
        try? version.write(toFile: manifestPath, atomically: true, encoding: .utf8)
    }
}
