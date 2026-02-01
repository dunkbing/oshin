//
//  GitContainerView.swift
//  oshin
//

import SwiftUI

// MARK: - Git Tab

struct GitTabView: View {
    @EnvironmentObject private var gitService: GitService

    let repository: Repository
    @Binding var selectedFile: String?
    let diffFontSize: Double

    @State private var sidebarTab: GitSidebarTab = .changes

    var body: some View {
        VStack(spacing: 0) {
            GitTabHeader(repository: repository)

            Divider()

            GitSidebarTabPicker(selectedTab: $sidebarTab)

            Divider()

            if gitService.isLoading {
                ProgressView("Loading git status...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    GitSidebarView(
                        selectedFile: selectedFile,
                        onFileClick: { file in
                            selectedFile = file
                            Task {
                                await gitService.loadFileDiff(for: file)
                            }
                        },
                        sidebarTab: $sidebarTab
                    )
                    .frame(minWidth: 250, idealWidth: 300)

                    // Right panel content based on selected tab
                    switch sidebarTab {
                    case .changes:
                        DiffView(
                            diffOutput: gitService.selectedFileDiff,
                            fileName: selectedFile ?? "",
                            fontSize: diffFontSize
                        )
                        .frame(minWidth: 400)
                    case .history:
                        CommitDetailView(fontSize: diffFontSize)
                            .frame(minWidth: 400)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Git Tab Header

struct GitTabHeader: View {
    @EnvironmentObject private var gitService: GitService

    let repository: Repository

    @State private var showingBranchPicker = false

    private var gitStatus: GitStatus { gitService.currentStatus }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(repository.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(repository.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if gitStatus.hasChanges {
                GitStatusView(
                    additions: gitStatus.additions,
                    deletions: gitStatus.deletions,
                    untrackedFiles: gitStatus.untrackedFiles.count
                )
            }

            Spacer()

            // Branch selector
            if !gitStatus.currentBranch.isEmpty {
                Button {
                    showingBranchPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(gitStatus.currentBranch)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingBranchPicker, arrowEdge: .bottom) {
                    BranchPickerPopover(
                        currentBranch: gitStatus.currentBranch,
                        onSelect: { branch in
                            gitService.checkout(branch: branch)
                            showingBranchPicker = false
                        }
                    )
                }
            }

            // Remote operations
            HStack(spacing: 4) {
                Button {
                    gitService.fetch()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("Fetch")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help("Fetch from remote")

                Button {
                    gitService.pull()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.to.line")
                        Text("Pull")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help("Pull from remote")

                Button {
                    gitService.push()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.to.line")
                        Text("Push")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help("Push to remote")
            }
            .disabled(gitService.isOperationPending)

            Divider()
                .frame(height: 20)

            // Refresh button
            Button {
                Task {
                    await gitService.reloadStatus()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refresh")
            .disabled(gitService.isLoading || gitService.isOperationPending)
        }
        .padding()
    }
}

// MARK: - Branch Picker Popover

struct BranchPickerPopover: View {
    @EnvironmentObject private var gitService: GitService

    let currentBranch: String
    let onSelect: (String) -> Void

    @State private var searchText = ""

    private var filteredBranches: [BranchInfo] {
        if searchText.isEmpty {
            return gitService.branches
        }
        return gitService.branches.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search branches...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)

            Divider()

            // Branch list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredBranches) { branch in
                        Button {
                            onSelect(branch.name)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: branch.isRemote ? "cloud" : "arrow.triangle.branch")
                                    .font(.system(size: 11))
                                    .foregroundStyle(branch.isRemote ? .blue : .secondary)
                                    .frame(width: 16)

                                Text(branch.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)

                                Spacer()

                                if branch.name == currentBranch {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            branch.name == currentBranch
                                ? Color.blue.opacity(0.1) : Color.clear
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 250)
        .onAppear {
            Task {
                await gitService.loadBranches()
            }
        }
    }
}
