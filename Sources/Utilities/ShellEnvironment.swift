//
//  ShellEnvironment.swift
//  agentmonitor
//
//  User shell environment loading
//

import Foundation
import os.log

enum ShellEnvironment {
    nonisolated(unsafe) private static var cachedEnvironment: [String: String]?
    private static let cacheLock = NSLock()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.agentmonitor",
        category: "ShellEnvironment"
    )

    static func loadUserShellEnvironment() -> [String: String] {
        print("loadUserShellEnvironment: acquiring lock...")
        cacheLock.lock()
        defer {
            print("loadUserShellEnvironment: releasing lock")
            cacheLock.unlock()
        }

        if let cached = cachedEnvironment {
            print("loadUserShellEnvironment: returning cached (\(cached.count) vars)")
            return cached
        }

        print("loadUserShellEnvironment: isMainThread=\(Thread.isMainThread)")
        if Thread.isMainThread {
            print("loadUserShellEnvironment: on main thread, dispatching async and returning process env")
            DispatchQueue.global(qos: .utility).async {
                _ = loadUserShellEnvironment()
            }
            return ProcessInfo.processInfo.environment
        }

        print("loadUserShellEnvironment: loading from shell...")
        let env = loadEnvironmentFromShell()
        print("loadUserShellEnvironment: loaded \(env.count) vars from shell")
        cachedEnvironment = env
        return env
    }

    static func preloadEnvironment() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = loadUserShellEnvironment()
        }
    }

    static func reloadEnvironment() {
        cacheLock.lock()
        cachedEnvironment = nil
        cacheLock.unlock()
        preloadEnvironment()
    }

    private static func loadEnvironmentFromShell() -> [String: String] {
        let shell = getLoginShell()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        print("loadEnvironmentFromShell: shell=\(shell)")
        logger.info("Loading shell environment from: \(shell)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)

        let shellName = (shell as NSString).lastPathComponent
        // Don't use -i (interactive) as it can hang waiting for input
        let arguments: [String]
        switch shellName {
        case "fish":
            arguments = ["-l", "-c", "env"]
        case "zsh", "bash":
            arguments = ["-l", "-c", "env"]
        case "sh":
            arguments = ["-l", "-c", "env"]
        default:
            arguments = ["-c", "env"]
        }

        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: homeDir)

        // Provide empty stdin to prevent any blocking on input
        let stdinPipe = Pipe()
        try? stdinPipe.fileHandleForWriting.close()
        process.standardInput = stdinPipe

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        var shellEnv: [String: String] = [:]

        do {
            print("loadEnvironmentFromShell: running \(shell) \(arguments.joined(separator: " "))")
            logger.info("Running shell: \(shell) \(arguments.joined(separator: " "))")
            try process.run()
            print("loadEnvironmentFromShell: process started, waiting...")

            // Use a timeout to prevent hanging
            let deadline = Date().addingTimeInterval(10.0)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }

            if process.isRunning {
                print("loadEnvironmentFromShell: TIMEOUT - terminating")
                logger.warning("Shell environment loading timed out, terminating")
                process.terminate()
                try? pipe.fileHandleForReading.close()
                try? errorPipe.fileHandleForReading.close()
                return ProcessInfo.processInfo.environment
            }

            print("loadEnvironmentFromShell: process exited with status \(process.terminationStatus)")
            logger.info("Shell process exited with status: \(process.terminationStatus)")

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.split(separator: "\n") {
                    if let equalsIndex = line.firstIndex(of: "=") {
                        let key = String(line[..<equalsIndex])
                        let value = String(line[line.index(after: equalsIndex)...])
                        shellEnv[key] = value
                    }
                }
            }
            logger.info("Loaded \(shellEnv.count) environment variables")
        } catch {
            try? pipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            logger.error("Failed to load shell environment: \(error.localizedDescription)")
            return ProcessInfo.processInfo.environment
        }

        return shellEnv.isEmpty ? ProcessInfo.processInfo.environment : shellEnv
    }

    private static func getLoginShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }
        return "/bin/zsh"
    }
}

// Actor version for async contexts (used by installers)
actor ShellEnvironmentLoader {
    static let shared = ShellEnvironmentLoader()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.agentmonitor",
        category: "ShellEnvironmentLoader"
    )

    init() {}

    func loadShellEnvironment() -> [String: String] {
        print("ShellEnvironmentLoader: loadShellEnvironment called")
        logger.info("loadShellEnvironment called")
        let env = ShellEnvironment.loadUserShellEnvironment()
        print("ShellEnvironmentLoader: got \(env.count) env vars")
        logger.info("Returning \(env.count) environment variables")
        return env
    }
}
