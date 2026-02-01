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
    @State private var showingNewBranch = false

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

            // Branch selector with new branch button
            if !gitStatus.currentBranch.isEmpty {
                HStack(spacing: 0) {
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

                    Divider()
                        .frame(height: 16)

                    Button {
                        showingNewBranch = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .help("Create new branch")
                    .popover(isPresented: $showingNewBranch, arrowEdge: .bottom) {
                        NewBranchPopover(
                            currentBranch: gitStatus.currentBranch,
                            onCreate: { name, baseBranch in
                                gitService.createBranch(name: name, baseBranch: baseBranch)
                                showingNewBranch = false
                            },
                            onCancel: {
                                showingNewBranch = false
                            }
                        )
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                )
            }

            // Remote operations
            HStack(spacing: 0) {
                Button {
                    gitService.fetch()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Fetch")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .help("Fetch from remote")

                Divider()
                    .frame(height: 16)

                Button {
                    gitService.pull()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text("Pull")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .help("Pull from remote")

                Divider()
                    .frame(height: 16)

                Button {
                    gitService.push()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text("Push")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .help("Push to remote")
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )
            .opacity(gitService.isOperationPending ? 0.5 : 1)
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

// MARK: - New Branch Popover

struct NewBranchPopover: View {
    @EnvironmentObject private var gitService: GitService

    let currentBranch: String
    let onCreate: (String, String) -> Void
    let onCancel: () -> Void

    @State private var branchName = ""
    @State private var selectedBaseBranch: String = ""
    @State private var showingBaseBranchPicker = false

    private var localBranches: [BranchInfo] {
        gitService.branches.filter { !$0.isRemote }
    }

    private var isValid: Bool {
        !branchName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Branch")
                .font(.system(size: 13, weight: .semibold))

            // Branch name input
            VStack(alignment: .leading, spacing: 4) {
                Text("Branch name")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("feature/my-branch", text: $branchName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            // Base branch selector
            VStack(alignment: .leading, spacing: 4) {
                Text("Based on")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(localBranches) { branch in
                        Button {
                            selectedBaseBranch = branch.name
                        } label: {
                            HStack {
                                Text(branch.name)
                                if branch.name == selectedBaseBranch {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(selectedBaseBranch.isEmpty ? currentBranch : selectedBaseBranch)
                            .font(.system(size: 12))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
            }

            Divider()

            // Action buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    let baseBranch = selectedBaseBranch.isEmpty ? currentBranch : selectedBaseBranch
                    onCreate(branchName.trimmingCharacters(in: .whitespaces), baseBranch)
                } label: {
                    Text("Create Branch")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isValid ? Color.accentColor : Color.accentColor.opacity(0.5))
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            selectedBaseBranch = currentBranch
            Task {
                await gitService.loadBranches()
            }
        }
    }
}
