//
//  AgentFileSystemDelegate.swift
//  oshin
//
//  Handles file system operations for agent sessions
//

import Foundation
import os.log

actor AgentFileSystemDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.oshin",
        category: "FileSystemDelegate"
    )

    init() {}

    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?)
        async throws -> ReadTextFileResponse
    {
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        let filteredContent: String
        if let startLine = line, let lineLimit = limit {
            let startIdx = max(0, startLine - 1)
            let endIdx = min(lines.count, startIdx + lineLimit)
            filteredContent = lines[startIdx..<endIdx].joined(separator: "\n")
        } else if let startLine = line {
            let startIdx = max(0, startLine - 1)
            filteredContent = lines[startIdx...].joined(separator: "\n")
        } else {
            filteredContent = content
        }

        return ReadTextFileResponse(content: filteredContent, totalLines: lines.count, _meta: nil)
    }

    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws
        -> WriteTextFileResponse
    {
        logger.info("Write request for: \(path) (\(content.count) chars)")
        let url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default

        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            logger.info("Write succeeded: \(path)")
            return WriteTextFileResponse(_meta: nil)
        } catch {
            logger.error("Write failed for \(path): \(error.localizedDescription)")
            throw error
        }
    }
}
