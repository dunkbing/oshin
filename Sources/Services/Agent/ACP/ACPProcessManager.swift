//
//  ACPProcessManager.swift
//  agentmonitor
//
//  Manages subprocess lifecycle, I/O pipes, and message serialization
//

import Darwin
import Foundation
import os.log

actor ACPProcessManager {
    // MARK: - Properties

    private var process: Process?
    private var processGroupId: pid_t?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var readBuffer: Data = Data()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: Logger

    private var onDataReceived: ((Data) async -> Void)?
    private var onTermination: ((Int32) async -> Void)?

    // MARK: - Initialization

    init(encoder: JSONEncoder, decoder: JSONDecoder) {
        self.encoder = encoder
        self.decoder = decoder
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.agentmonitor",
            category: "ACPProcessManager"
        )
    }

    // MARK: - Process Lifecycle

    func launch(agentPath: String, arguments: [String] = [], workingDirectory: String? = nil)
        throws
    {
        guard process == nil else {
            throw ACPClientError.invalidResponse
        }

        logger.info("Launching agent: \(agentPath) with args: \(arguments)")

        let proc = Process()

        let resolvedPath =
            (try? FileManager.default.destinationOfSymbolicLink(atPath: agentPath)) ?? agentPath
        let actualPath =
            resolvedPath.hasPrefix("/")
            ? resolvedPath
            : ((agentPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(resolvedPath)

        let isNodeScript: Bool = {
            guard let handle = FileHandle(forReadingAtPath: actualPath) else { return false }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 64),
                let firstLine = String(data: data, encoding: .utf8)
            else { return false }
            return firstLine.hasPrefix("#!/usr/bin/env node")
        }()

        if isNodeScript {
            let searchPaths = [
                (agentPath as NSString).deletingLastPathComponent,
                (actualPath as NSString).deletingLastPathComponent,
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
            ]

            var foundNode: String?
            for searchPath in searchPaths {
                let nodePath = (searchPath as NSString).appendingPathComponent("node")
                if FileManager.default.fileExists(atPath: nodePath) {
                    foundNode = nodePath
                    break
                }
            }

            if let nodePath = foundNode {
                proc.executableURL = URL(fileURLWithPath: nodePath)
                proc.arguments = [actualPath] + arguments
            } else {
                proc.executableURL = URL(fileURLWithPath: agentPath)
                proc.arguments = arguments
            }
        } else {
            proc.executableURL = URL(fileURLWithPath: agentPath)
            proc.arguments = arguments
        }

        var environment = ShellEnvironment.loadUserShellEnvironment()

        if let workingDirectory, !workingDirectory.isEmpty {
            environment["PWD"] = workingDirectory
            environment["OLDPWD"] = workingDirectory
            proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let agentDir = (agentPath as NSString).deletingLastPathComponent
        if let existingPath = environment["PATH"] {
            environment["PATH"] = "\(agentDir):\(existingPath)"
        } else {
            environment["PATH"] = agentDir
        }

        proc.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr

        proc.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(exitCode: process.terminationStatus)
            }
        }

        try proc.run()
        process = proc
        processGroupId = nil
        if proc.processIdentifier > 0 {
            let pid = proc.processIdentifier
            logger.info("Agent process started with PID: \(pid)")
            if setpgid(pid, pid) == 0 {
                processGroupId = pid
            }
        }

        startReading()
        startReadingStderr()
        logger.info("Agent I/O pipes configured")
    }

    func isRunning() -> Bool {
        return process?.isRunning == true
    }

    func terminate() async {
        let proc = process
        let pgid = processGroupId

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        try? stdinPipe?.fileHandleForWriting.close()
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()

        if let proc, proc.isRunning {
            if let pgid {
                _ = killpg(pgid, SIGTERM)
            } else {
                proc.terminate()
            }
        }

        if let proc {
            let exited = await waitForExit(proc, timeout: 2.0)
            if !exited, proc.processIdentifier > 0 {
                if let pgid {
                    _ = killpg(pgid, SIGKILL)
                } else {
                    _ = kill(proc.processIdentifier, SIGKILL)
                }
            }
        }

        process = nil
        processGroupId = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        readBuffer.removeAll()
    }

    // MARK: - I/O Operations

    func writeMessage<T: Encodable>(_ message: T) async throws {
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            logger.error("Cannot write - stdin pipe not available")
            throw ACPClientError.processNotRunning
        }

        let data = try encoder.encode(message)
        var lineData = data
        lineData.append(0x0A)

        if let jsonString = String(data: data, encoding: .utf8) {
            logger.debug(">>> Sending: \(jsonString.prefix(500))")
        }

        try stdin.write(contentsOf: lineData)
    }

    // MARK: - Callbacks

    func setDataReceivedCallback(_ callback: @escaping (Data) async -> Void) {
        self.onDataReceived = callback
    }

    func setTerminationCallback(_ callback: @escaping (Int32) async -> Void) {
        self.onTermination = callback
    }

    // MARK: - Private Methods

    private func startReading() {
        guard let stdout = stdoutPipe?.fileHandleForReading else { return }

        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            Task {
                await self?.processIncomingData(data)
            }
        }
    }

    private func startReadingStderr() {
        guard let stderr = stderrPipe?.fileHandleForReading else { return }

        stderr.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    Logger(
                        subsystem: Bundle.main.bundleIdentifier ?? "com.agentmonitor",
                        category: "ACPProcessManager"
                    ).warning("Agent stderr: \(text)")
                }
            }
        }
    }

    private func processIncomingData(_ data: Data) async {
        if let text = String(data: data, encoding: .utf8) {
            logger.debug("<<< Received raw: \(text.prefix(500))")
        }
        readBuffer.append(data)
        await drainBufferedMessages()
    }

    private func handleTermination(exitCode: Int32) async {
        await drainAndClosePipes()
        logger.info("Agent process terminated with code: \(exitCode)")
        await onTermination?(exitCode)
    }

    private func drainAndClosePipes() async {
        if let stdoutHandle = stdoutPipe?.fileHandleForReading {
            stdoutHandle.readabilityHandler = nil
            do {
                while true {
                    guard let chunk = try stdoutHandle.read(upToCount: 65536), !chunk.isEmpty else {
                        break
                    }
                    await processIncomingData(chunk)
                }
            } catch {}
            try? stdoutHandle.close()
        }

        if let stderrHandle = stderrPipe?.fileHandleForReading {
            stderrHandle.readabilityHandler = nil
            do {
                while true {
                    guard let chunk = try stderrHandle.read(upToCount: 65536), !chunk.isEmpty else {
                        break
                    }
                }
            } catch {}
            try? stderrHandle.close()
        }

        await drainBufferedMessages()

        try? stdinPipe?.fileHandleForWriting.close()

        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        processGroupId = nil
        readBuffer.removeAll()
    }

    private func drainBufferedMessages() async {
        while let message = popNextMessage() {
            await onDataReceived?(message)
        }
    }

    private func popNextMessage() -> Data? {
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0D, 0x0A]
        while true {
            while let first = readBuffer.first, whitespace.contains(first) {
                readBuffer.removeFirst()
            }

            guard !readBuffer.isEmpty else {
                return nil
            }

            guard let first = readBuffer.first else { return nil }

            if first != 0x7B && first != 0x5B {
                if let newline = readBuffer.firstIndex(of: 0x0A) {
                    let removeCount =
                        readBuffer.distance(from: readBuffer.startIndex, to: newline) + 1
                    readBuffer.removeFirst(min(removeCount, readBuffer.count))
                    continue
                }

                if readBuffer.count > 4096 {
                    readBuffer.removeAll(keepingCapacity: true)
                }
                return nil
            }

            break
        }

        let bytes = Array(readBuffer)

        var depth = 0
        var inString = false
        var escaped = false

        for endIndex in 0..<bytes.count {
            let byte = bytes[endIndex]

            if inString {
                if escaped {
                    escaped = false
                    continue
                }
                if byte == 0x5C {
                    escaped = true
                    continue
                }
                if byte == 0x22 {
                    inString = false
                }
                continue
            }

            if byte == 0x22 {
                inString = true
                continue
            }

            if byte == 0x7B || byte == 0x5B {
                depth += 1
            } else if byte == 0x7D || byte == 0x5D {
                depth -= 1
                if depth == 0 {
                    let testData = Data(bytes[0...endIndex])
                    let removeCount = min(endIndex + 1, readBuffer.count)
                    readBuffer.removeFirst(removeCount)
                    return testData
                }
            }
        }

        return nil
    }

    private func waitForExit(_ proc: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !proc.isRunning
    }
}
