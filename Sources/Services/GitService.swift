//
//  GitService.swift
//  agentmonitor
//
//  Git operations service using SwiftGitX
//

import Foundation
import SwiftGitX

@MainActor
class GitService: ObservableObject {
    @Published private(set) var currentStatus: GitStatus = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var isOperationPending = false
    @Published private(set) var selectedFileDiff: String = ""

    private var repositoryPath: String = ""

    var repoPath: String { repositoryPath }

    func setRepositoryPath(_ path: String) {
        guard path != repositoryPath else { return }
        repositoryPath = path
        currentStatus = .empty
        selectedFileDiff = ""
        Task {
            await reloadStatus()
        }
    }

    // MARK: - Status

    func reloadStatus() async {
        guard !repositoryPath.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let status = try await loadGitStatus(at: repositoryPath)
            currentStatus = status
        } catch {
            print("Failed to load git status: \(error)")
            currentStatus = .empty
        }
    }

    // MARK: - Staging

    func stageFile(_ file: String) {
        let path = repositoryPath
        let isDeleted = currentStatus.deletedFiles.contains(file)

        // Optimistic update - modify arrays in place conceptually
        var newStaged = currentStatus.stagedFiles
        var newModified = currentStatus.modifiedFiles
        var newDeleted = currentStatus.deletedFiles
        var newUntracked = currentStatus.untrackedFiles

        if !newStaged.contains(file) {
            newStaged.append(file)
        }
        newModified.removeAll { $0 == file }
        newDeleted.removeAll { $0 == file }
        newUntracked.removeAll { $0 == file }

        // Single update to trigger one view refresh
        currentStatus = currentStatus.with(
            stagedFiles: newStaged,
            modifiedFiles: newModified,
            deletedFiles: newDeleted,
            untrackedFiles: newUntracked
        )

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                if isDeleted {
                    try GitService.runGitCommand(["add", "--", file], in: path)
                } else {
                    let url = URL(fileURLWithPath: path)
                    let repository = try SwiftGitX.Repository(at: url, createIfNotExists: false)
                    try repository.add(path: file)
                }
            } catch {
                print("Failed to stage file: \(error)")
                await self?.reloadStatus()
            }
        }
    }

    func unstageFile(_ file: String) {
        let path = repositoryPath

        // Optimistic update - move file from staged back to appropriate category
        var newStaged = currentStatus.stagedFiles
        var newModified = currentStatus.modifiedFiles

        newStaged.removeAll { $0 == file }
        if !newModified.contains(file) {
            newModified.append(file)
        }

        // Single update to trigger one view refresh
        currentStatus = currentStatus.with(
            stagedFiles: newStaged,
            modifiedFiles: newModified
        )

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let url = URL(fileURLWithPath: path)
                let repository = try SwiftGitX.Repository(at: url, createIfNotExists: false)
                try repository.restore(.staged, paths: [file])
            } catch {
                print("Failed to unstage file: \(error)")
                await self?.reloadStatus()
            }
        }
    }

    func stageAll(completion: (@Sendable () -> Void)? = nil) {
        guard !isOperationPending else { return }
        isOperationPending = true

        let path = repositoryPath
        let filesToAdd = currentStatus.modifiedFiles + currentStatus.untrackedFiles
        let filesToRemove = currentStatus.deletedFiles
        Task { [weak self] in
            await Task.detached(priority: .userInitiated) {
                do {
                    let url = URL(fileURLWithPath: path)
                    let repository = try SwiftGitX.Repository(at: url, createIfNotExists: false)
                    if !filesToAdd.isEmpty {
                        try repository.add(paths: filesToAdd)
                    }
                    // Use git command for deleted files
                    for file in filesToRemove {
                        try GitService.runGitCommand(["add", "--", file], in: path)
                    }
                } catch {
                    print("Failed to stage all: \(error)")
                }
            }.value

            self?.isOperationPending = false
            completion?()
            await self?.reloadStatus()
        }
    }

    func unstageAll() {
        guard !isOperationPending else { return }
        isOperationPending = true

        let path = repositoryPath
        let stagedFiles = currentStatus.stagedFiles
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let url = URL(fileURLWithPath: path)
                let repository = try SwiftGitX.Repository(at: url, createIfNotExists: false)
                if !stagedFiles.isEmpty {
                    try repository.restore(.staged, paths: stagedFiles)
                }
            } catch {
                print("Failed to unstage all: \(error)")
            }

            await MainActor.run { [weak self] in
                self?.isOperationPending = false
            }
            await self?.reloadStatus()
        }
    }

    // MARK: - Commit

    func commit(message: String) {
        guard !isOperationPending, !message.isEmpty, !currentStatus.stagedFiles.isEmpty else { return }
        isOperationPending = true

        let path = repositoryPath
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let url = URL(fileURLWithPath: path)
                let repository = try SwiftGitX.Repository(at: url, createIfNotExists: false)
                try repository.commit(message: message)
            } catch {
                print("Failed to commit: \(error)")
            }

            await MainActor.run { [weak self] in
                self?.isOperationPending = false
            }
            await self?.reloadStatus()
        }
    }

    func amendCommit(message: String?) {
        guard !isOperationPending else { return }
        isOperationPending = true

        let path = repositoryPath
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                var args = ["commit", "--amend"]
                if let message = message {
                    args += ["-m", message]
                } else {
                    args += ["--no-edit"]
                }
                try GitService.runGitCommand(args, in: path)
            } catch {
                print("Failed to amend commit: \(error)")
            }

            await MainActor.run { [weak self] in
                self?.isOperationPending = false
            }
            await self?.reloadStatus()
        }
    }

    // MARK: - Diff

    func loadFileDiff(for file: String) async {
        let path = repositoryPath
        do {
            let diffOutput = try await Task.detached(priority: .utility) {
                let url = URL(fileURLWithPath: path)
                let repository = try SwiftGitX.Repository(at: url, createIfNotExists: false)

                // Get diff for this specific file
                let diff = try repository.diff(to: [.workingTree, .index])
                var output = ""

                for patch in diff.patches {
                    let filePath = patch.delta.newFile.path
                    if filePath == file {
                        output += "diff --git a/\(filePath) b/\(filePath)\n"

                        for hunk in patch.hunks {
                            output += hunk.header
                            for line in hunk.lines {
                                let prefix: String
                                switch line.type {
                                case .addition, .additionEOF:
                                    prefix = "+"
                                case .deletion, .deletionEOF:
                                    prefix = "-"
                                default:
                                    prefix = " "
                                }
                                output += prefix + line.content
                            }
                        }
                        break
                    }
                }

                return output
            }.value

            selectedFileDiff = diffOutput
        } catch {
            print("Failed to load diff: \(error)")
            selectedFileDiff = ""
        }
    }

    // MARK: - Private

    private func loadGitStatus(at path: String) async throws -> GitStatus {
        try await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path)
            let repository = try SwiftGitX.Repository(at: url, createIfNotExists: false)

            // Get status entries
            let statusEntries = try repository.status()

            // Categorize files
            var stagedFiles: [String] = []
            var modifiedFiles: [String] = []
            var deletedFiles: [String] = []
            var untrackedFiles: [String] = []
            var conflictedFiles: [String] = []

            for entry in statusEntries {
                let filePath = entry.index?.newFile.path ?? entry.workingTree?.newFile.path ?? ""

                for status in entry.status {
                    switch status {
                    case .indexNew, .indexModified, .indexDeleted, .indexRenamed, .indexTypeChange:
                        if !stagedFiles.contains(filePath) {
                            stagedFiles.append(filePath)
                        }
                    case .workingTreeDeleted:
                        if !deletedFiles.contains(filePath) {
                            deletedFiles.append(filePath)
                        }
                    case .workingTreeModified, .workingTreeRenamed, .workingTreeTypeChange:
                        if !modifiedFiles.contains(filePath) {
                            modifiedFiles.append(filePath)
                        }
                    case .workingTreeNew:
                        if !untrackedFiles.contains(filePath) {
                            untrackedFiles.append(filePath)
                        }
                    case .conflicted:
                        if !conflictedFiles.contains(filePath) {
                            conflictedFiles.append(filePath)
                        }
                    default:
                        break
                    }
                }
            }

            // Get current branch
            var currentBranch = ""
            if let head = try? repository.HEAD {
                currentBranch = head.name
            }

            // Get diff stats (additions/deletions)
            var additions = 0
            var deletions = 0

            if let diff = try? repository.diff(to: [.workingTree, .index]) {
                for patch in diff.patches {
                    for hunk in patch.hunks {
                        for line in hunk.lines {
                            switch line.type {
                            case .addition, .additionEOF:
                                additions += 1
                            case .deletion, .deletionEOF:
                                deletions += 1
                            default:
                                break
                            }
                        }
                    }
                }
            }

            return GitStatus(
                stagedFiles: stagedFiles,
                modifiedFiles: modifiedFiles,
                deletedFiles: deletedFiles,
                untrackedFiles: untrackedFiles,
                conflictedFiles: conflictedFiles,
                currentBranch: currentBranch,
                aheadCount: 0,
                behindCount: 0,
                additions: additions,
                deletions: deletions
            )
        }.value
    }

    // MARK: - Git Shell Commands

    private nonisolated static func runGitCommand(_ arguments: [String], in directory: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "GitService", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output])
        }
    }
}
