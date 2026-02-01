//
//  GitStatus.swift
//  oshin
//
//  Git status representation
//

import Foundation

struct GitStatus: Equatable {
    let stagedFiles: [String]
    let modifiedFiles: [String]
    let deletedFiles: [String]
    let untrackedFiles: [String]
    let conflictedFiles: [String]
    let currentBranch: String
    let aheadCount: Int
    let behindCount: Int
    let additions: Int
    let deletions: Int

    var hasChanges: Bool {
        totalChanges > 0
    }

    var totalChanges: Int {
        stagedFiles.count + modifiedFiles.count + deletedFiles.count + untrackedFiles.count
    }

    static let empty = GitStatus(
        stagedFiles: [],
        modifiedFiles: [],
        deletedFiles: [],
        untrackedFiles: [],
        conflictedFiles: [],
        currentBranch: "",
        aheadCount: 0,
        behindCount: 0,
        additions: 0,
        deletions: 0
    )

    /// Create a copy with updated file arrays (for optimistic updates)
    func with(
        stagedFiles: [String]? = nil,
        modifiedFiles: [String]? = nil,
        deletedFiles: [String]? = nil,
        untrackedFiles: [String]? = nil
    ) -> GitStatus {
        GitStatus(
            stagedFiles: stagedFiles ?? self.stagedFiles,
            modifiedFiles: modifiedFiles ?? self.modifiedFiles,
            deletedFiles: deletedFiles ?? self.deletedFiles,
            untrackedFiles: untrackedFiles ?? self.untrackedFiles,
            conflictedFiles: self.conflictedFiles,
            currentBranch: self.currentBranch,
            aheadCount: self.aheadCount,
            behindCount: self.behindCount,
            additions: self.additions,
            deletions: self.deletions
        )
    }
}
