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

    private var repositoryPath: String = ""

    func setRepositoryPath(_ path: String) {
        guard path != repositoryPath else { return }
        repositoryPath = path
        currentStatus = .empty
        Task {
            await reloadStatus()
        }
    }

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

    private func loadGitStatus(at path: String) async throws -> GitStatus {
        try await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path)
            let repository = try SwiftGitX.Repository(at: url, createIfNotExists: false)

            // Get status entries
            let statusEntries = try repository.status()

            // Categorize files
            var stagedFiles: [String] = []
            var modifiedFiles: [String] = []
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
                    case .workingTreeModified, .workingTreeDeleted, .workingTreeRenamed, .workingTreeTypeChange:
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
                untrackedFiles: untrackedFiles,
                conflictedFiles: conflictedFiles,
                currentBranch: currentBranch,
                aheadCount: 0,  // TODO: implement ahead/behind
                behindCount: 0,
                additions: additions,
                deletions: deletions
            )
        }.value
    }
}
