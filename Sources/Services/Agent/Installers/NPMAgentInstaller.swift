//
//  NPMAgentInstaller.swift
//  oshin
//
//  NPM/Bun package installation for ACP agents
//

import Foundation

enum PackageManager: String {
    case bun
    case npm

    var installCommand: [String] {
        switch self {
        case .bun:
            return ["bun", "install"]
        case .npm:
            return ["npm", "install"]
        }
    }

    func prefixArgs(for targetDir: String) -> [String] {
        switch self {
        case .bun:
            return ["--cwd", targetDir]
        case .npm:
            return ["--prefix", targetDir]
        }
    }
}

actor NPMAgentInstaller {
    static let shared = NPMAgentInstaller()

    private let shellLoader: ShellEnvironmentLoader

    init(shellLoader: ShellEnvironmentLoader = .shared) {
        self.shellLoader = shellLoader
    }

    // MARK: - Package Manager Detection

    private func detectPackageManager(shellEnv: [String: String]) -> PackageManager {
        // Check if bun is available
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "bun"]
        process.environment = shellEnv

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !path.isEmpty
                {
                    print("Found bun at: \(path)")
                    return .bun
                }
            }
        } catch {
            print("Error checking for bun: \(error)")
        }

        print("Bun not found, falling back to npm")
        return .npm
    }

    // MARK: - Installation

    func install(package: String, targetDir: String) async throws {
        print("Package install starting for: \(package)")
        print("Target directory: \(targetDir)")

        let shellEnv = await shellLoader.loadShellEnvironment()
        print("Shell environment loaded with PATH: \(shellEnv["PATH"] ?? "nil")")

        let packageManager = detectPackageManager(shellEnv: shellEnv)
        print("Using package manager: \(packageManager.rawValue)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        var args = packageManager.installCommand
        args.append(contentsOf: packageManager.prefixArgs(for: targetDir))
        args.append(package)
        process.arguments = args

        print("Running: \(args.joined(separator: " "))")

        process.environment = shellEnv

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        print("Starting \(packageManager.rawValue) process...")
        try process.run()
        print("\(packageManager.rawValue) process started, waiting for exit...")
        process.waitUntilExit()
        print("\(packageManager.rawValue) process exited with status: \(process.terminationStatus)")

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
            print("\(packageManager.rawValue) stdout: \(output.prefix(500))")
        }
        if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
            print("\(packageManager.rawValue) stderr: \(errorOutput.prefix(500))")
        }

        try? pipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("\(packageManager.rawValue) install failed: \(errorMessage)")
            throw AgentInstallError.installFailed(message: errorMessage)
        }

        if let version = getInstalledVersion(package: package, targetDir: targetDir) {
            saveVersionManifest(version: version, targetDir: targetDir)
            print("Successfully installed \(package) version \(version) using \(packageManager.rawValue)")
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
