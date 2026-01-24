//
//  GitSidebarView.swift
//  agentmonitor
//
//  Git sidebar with file list and commit section
//

import SwiftUI

struct GitSidebarView: View {
    let gitStatus: GitStatus
    let isOperationPending: Bool
    let selectedFile: String?

    var onStageFile: (String) -> Void
    var onUnstageFile: (String) -> Void
    var onStageAll: (@escaping @Sendable () -> Void) -> Void
    var onUnstageAll: () -> Void
    var onCommit: (String) -> Void
    var onFileClick: (String) -> Void

    @State private var commitMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            GitSidebarHeader(
                gitStatus: gitStatus,
                isOperationPending: isOperationPending,
                hasUnstagedChanges: hasUnstagedChanges,
                onStageAll: onStageAll,
                onUnstageAll: onUnstageAll
            )

            Divider()

            // File list (expands to fill available space)
            GitFileListView(
                gitStatus: gitStatus,
                isOperationPending: isOperationPending,
                selectedFile: selectedFile,
                onStageFile: onStageFile,
                onUnstageFile: onUnstageFile,
                onFileClick: onFileClick
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            Divider()

            // Commit section (fixed at bottom)
            GitCommitSection(
                gitStatus: gitStatus,
                isOperationPending: isOperationPending,
                commitMessage: $commitMessage,
                onCommit: onCommit,
                onStageAll: onStageAll
            )
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hasUnstagedChanges: Bool {
        !gitStatus.modifiedFiles.isEmpty || !gitStatus.untrackedFiles.isEmpty
    }
}

// MARK: - Header

struct GitSidebarHeader: View {
    let gitStatus: GitStatus
    let isOperationPending: Bool
    let hasUnstagedChanges: Bool
    let onStageAll: (@escaping @Sendable () -> Void) -> Void
    let onUnstageAll: () -> Void

    var body: some View {
        HStack {
            Text("\(gitStatus.totalChanges) Changes")
                .font(.system(size: 12, weight: .medium))

            Spacer()

            if hasUnstagedChanges {
                Button("Stage All") {
                    onStageAll {}
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .disabled(isOperationPending)
            }

            Menu {
                Button("Unstage All") {
                    onUnstageAll()
                }
                .disabled(gitStatus.stagedFiles.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            .disabled(isOperationPending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
