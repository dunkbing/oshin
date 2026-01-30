//
//  GitSidebarView.swift
//  agentmonitor
//
//  Git sidebar with file list, commit section, and history
//

import SwiftUI

// MARK: - Sidebar Tab

enum GitSidebarTab: String, CaseIterable {
    case changes = "Changes"
    case history = "History"
}

// MARK: - Git Sidebar View

struct GitSidebarView: View {
    @EnvironmentObject private var gitService: GitService

    let selectedFile: String?
    let onFileClick: (String) -> Void
    @Binding var sidebarTab: GitSidebarTab

    @State private var commitMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            GitSidebarTabPicker(selectedTab: $sidebarTab)

            Divider()

            // Tab content
            switch sidebarTab {
            case .changes:
                GitChangesTab(
                    selectedFile: selectedFile,
                    onFileClick: onFileClick,
                    commitMessage: $commitMessage
                )
            case .history:
                GitHistoryTab()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { $0.animation = nil }
    }
}

// MARK: - Tab Picker

struct GitSidebarTabPicker: View {
    @Binding var selectedTab: GitSidebarTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GitSidebarTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selectedTab == tab ? Color.primary.opacity(0.1) : Color.clear)
                        )
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

// MARK: - Changes Tab

struct GitChangesTab: View {
    @EnvironmentObject private var gitService: GitService

    let selectedFile: String?
    let onFileClick: (String) -> Void
    @Binding var commitMessage: String

    private var gitStatus: GitStatus { gitService.currentStatus }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            GitChangesHeader()

            Divider()

            if gitStatus.hasChanges {
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
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Changes")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Working tree is clean")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Changes Header

struct GitChangesHeader: View {
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

// MARK: - History Tab

struct GitHistoryTab: View {
    @EnvironmentObject private var gitService: GitService

    var body: some View {
        VStack(spacing: 0) {
            // Header
            GitHistoryHeader()

            Divider()

            // Commit log
            GitLogView()
        }
    }
}

// MARK: - History Header

struct GitHistoryHeader: View {
    @EnvironmentObject private var gitService: GitService

    var body: some View {
        HStack {
            Text("Commit History")
                .font(.system(size: 12, weight: .medium))

            Spacer()

            Button {
                Task {
                    await gitService.loadCommitLog()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .disabled(gitService.isLoadingLog)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
