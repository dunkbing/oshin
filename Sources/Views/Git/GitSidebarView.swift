//
//  GitSidebarView.swift
//  agentmonitor
//
//  Git sidebar with file list and commit section
//

import SwiftUI

struct GitSidebarView: View {
    @EnvironmentObject private var gitService: GitService

    let selectedFile: String?
    let onFileClick: (String) -> Void

    @State private var commitMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            GitSidebarHeader()

            Divider()

            // File list (expands to fill available space)
            GitFileListView(
                selectedFile: selectedFile,
                onFileClick: onFileClick
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            Divider()

            // Commit section (fixed at bottom)
            GitCommitSection(commitMessage: $commitMessage)
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { $0.animation = nil }
    }
}

// MARK: - Header

struct GitSidebarHeader: View {
    @EnvironmentObject private var gitService: GitService

    private var gitStatus: GitStatus { gitService.currentStatus }

    private var hasUnstagedChanges: Bool {
        !gitStatus.modifiedFiles.isEmpty || !gitStatus.untrackedFiles.isEmpty || !gitStatus.deletedFiles.isEmpty
    }

    var body: some View {
        HStack {
            Text("\(gitStatus.totalChanges) Changes")
                .font(.system(size: 12, weight: .medium))

            Spacer()

            if hasUnstagedChanges {
                Button("Stage All") {
                    gitService.stageAll {}
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .disabled(gitService.isOperationPending)
            }

            Menu {
                Button("Unstage All") {
                    gitService.unstageAll()
                }
                .disabled(gitStatus.stagedFiles.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(gitService.isOperationPending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
