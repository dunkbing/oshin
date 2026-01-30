//
//  GitService.swift
//  agentmonitor
//
//  Git operations service using SwiftGitX
//

import Foundation
import SwiftGitX
import SwiftUI

// MARK: - Commit Info Model

struct CommitInfo: Identifiable, Equatable {
    let id: String
    let shortId: String
    let summary: String
    let body: String?
    let authorName: String
    let authorEmail: String
    let date: Date
    let parentIds: [String]

    var authorInitial: String {
        String(authorName.prefix(1)).uppercased()
    }

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Commit File Change Model

struct CommitFileChange: Identifiable, Equatable {
    let id: String
    let path: String
    let changeType: FileChangeType
    let additions: Int
    let deletions: Int
    let diffOutput: String

    enum FileChangeType: String {
        case added = "A"
        case deleted = "D"
        case modified = "M"
        case renamed = "R"
        case copied = "C"

        var color: Color {
            switch self {
            case .added: return .green
            case .deleted: return .red
            case .modified: return .orange
            case .renamed: return .blue
            case .copied: return .purple
            }
        }

        var icon: String {
            switch self {
            case .added: return "plus.circle.fill"
            case .deleted: return "minus.circle.fill"
            case .modified: return "pencil.circle.fill"
            case .renamed: return "arrow.right.circle.fill"
            case .copied: return "doc.on.doc.fill"
            }
        }
    }
}

// MARK: - Commit Detail Model

struct CommitDetail: Equatable {
    let commit: CommitInfo
    let files: [CommitFileChange]
    let totalAdditions: Int
    let totalDeletions: Int

    static func == (lhs: CommitDetail, rhs: CommitDetail) -> Bool {
        lhs.commit.id == rhs.commit.id
    }
}

@MainActor
class GitService: ObservableObject {
    @Published private(set) var currentStatus: GitStatus = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var isOperationPending = false
    @Published private(set) var selectedFileDiff: String = ""
    @Published private(set) var commitLog: [CommitInfo] = []
    @Published private(set) var isLoadingLog = false
    @Published private(set) var hasMoreCommits = true
    @Published private(set) var totalCommitCount: Int?
    @Published private(set) var selectedCommitDetail: CommitDetail?
    @Published private(set) var isLoadingCommitDetail = false
    @Published var selectedCommitId: String?

    private var repositoryPath: String = ""
    private let logPageSize = 50

    var repoPath: String { repositoryPath }

    func setRepositoryPath(_ path: String) {
        guard path != repositoryPath else { return }
        repositoryPath = path
        currentStatus = .empty
        selectedFileDiff = ""
        commitLog = []
        hasMoreCommits = true
        totalCommitCount = nil
        selectedCommitId = nil
        selectedCommitDetail = nil
        Task {
            await reloadStatus()
        }
    }

    // MARK: - Log

    func loadCommitLog() async {
        guard !repositoryPath.isEmpty, !isLoadingLog else { return }

        isLoadingLog = true
        defer { isLoadingLog = false }

        do {
            async let commitsTask = fetchCommits(skip: 0, limit: logPageSize)
            async let countTask = fetchTotalCommitCount()

            let (commits, count) = try await (commitsTask, countTask)

            commitLog = commits
            hasMoreCommits = commits.count >= logPageSize
            totalCommitCount = count
        } catch {
            print("Failed to load commit log: \(error)")
            commitLog = []
            hasMoreCommits = false
            totalCommitCount = nil
        }
    }

    private func fetchTotalCommitCount() async throws -> Int {
        let path = repositoryPath
        return try await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path)
            let repository = try SwiftGitX.Repository(at: url, createIfNotExists: false)

            let sequence = try repository.log(sorting: .none)
            var count = 0
            for _ in sequence {
                count += 1
            }
            return count
        }.value
    }

    func loadMoreCommits() async {
        guard !repositoryPath.isEmpty, !isLoadingLog, hasMoreCommits else { return }

        isLoadingLog = true
        defer { isLoadingLog = false }

        do {
            let commits = try await fetchCommits(skip: commitLog.count, limit: logPageSize)
            if commits.isEmpty {
                hasMoreCommits = false
            } else {
                commitLog.append(contentsOf: commits)
                hasMoreCommits = commits.count >= logPageSize
            }
        } catch {
            print("Failed to load more commits: \(error)")
            hasMoreCommits = false
        }
    }

    private func fetchCommits(skip: Int, limit: Int) async throws -> [CommitInfo] {
        let path = repositoryPath
        return try await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path)
            let repository = try SwiftGitX.Repository(at: url, createIfNotExists: false)

            let sequence = try repository.log(sorting: .time)
            var commits: [CommitInfo] = []
            var count = 0
            var skipped = 0

            for commit in sequence {
                if skipped < skip {
                    skipped += 1
                    continue
                }

                if count >= limit {
                    break
                }

                let idString = commit.id.hex
                let shortId = String(idString.prefix(7))

                let parentIds = (try? commit.parents.map { $0.id.hex }) ?? []

                commits.append(
                    CommitInfo(
                        id: idString,
                        shortId: shortId,
                        summary: commit.summary,
                        body: commit.body,
                        authorName: commit.author.name,
                        authorEmail: commit.author.email,
                        date: commit.date,
                        parentIds: parentIds
                    ))

                count += 1
            }

            return commits
        }.value
    }

    // MARK: - Commit Detail

    func loadCommitDetail(for commitId: String) async {
        guard !repositoryPath.isEmpty else { return }

        // Find the commit info from the log
        guard let commitInfo = commitLog.first(where: { $0.id == commitId }) else { return }

        isLoadingCommitDetail = true
        selectedCommitId = commitId
        defer { isLoadingCommitDetail = false }

        do {
            let detail = try await fetchCommitDetail(commitId: commitId, commitInfo: commitInfo)
            selectedCommitDetail = detail
        } catch {
            print("Failed to load commit detail: \(error)")
            selectedCommitDetail = nil
        }
    }

    func clearSelectedCommit() {
        selectedCommitId = nil
        selectedCommitDetail = nil
    }

    private func fetchCommitDetail(commitId: String, commitInfo: CommitInfo) async throws -> CommitDetail {
        let path = repositoryPath
        return try await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path)
            let repository = try SwiftGitX.Repository(at: url, createIfNotExists: false)

            // Get the commit
            let oid = try SwiftGitX.OID(hex: commitId)
            let commit: SwiftGitX.Commit = try repository.show(id: oid)

            // Get the diff for this commit
            let diff = try repository.diff(commit: commit)

            var files: [CommitFileChange] = []
            var totalAdditions = 0
            var totalDeletions = 0

            for (index, delta) in diff.changes.enumerated() {
                let changeType: CommitFileChange.FileChangeType
                switch delta.type {
                case .added: changeType = .added
                case .deleted: changeType = .deleted
                case .renamed: changeType = .renamed
                case .copied: changeType = .copied
                default: changeType = .modified
                }

                // Build diff output for this file
                var diffOutput = ""
                if index < diff.patches.count {
                    let patch = diff.patches[index]
                    let filePath = delta.newFile.path

                    diffOutput += "diff --git a/\(filePath) b/\(filePath)\n"

                    for hunk in patch.hunks {
                        diffOutput += hunk.header
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
                            diffOutput += prefix + line.content
                        }
                    }
                }

                // Count additions and deletions
                var additions = 0
                var deletions = 0
                if index < diff.patches.count {
                    let patch = diff.patches[index]
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

                totalAdditions += additions
                totalDeletions += deletions

                files.append(
                    CommitFileChange(
                        id: delta.newFile.path,
                        path: delta.newFile.path,
                        changeType: changeType,
                        additions: additions,
                        deletions: deletions,
                        diffOutput: diffOutput
                    ))
            }

            return CommitDetail(
                commit: commitInfo,
                files: files,
                totalAdditions: totalAdditions,
                totalDeletions: totalDeletions
            )
        }.value
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
