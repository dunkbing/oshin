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
    @State private var showingRemoteConfig = false

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
                        if gitStatus.behindCount > 0 {
                            Text("\(gitStatus.behindCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Color.blue)
                                )
                                .foregroundStyle(.white)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .help(
                    gitStatus.behindCount > 0
                        ? "Pull \(gitStatus.behindCount) commit(s) from remote" : "Pull from remote")

                Divider()
                    .frame(height: 16)

                Button {
                    gitService.push()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text("Push")
                        if gitStatus.aheadCount > 0 {
                            Text("\(gitStatus.aheadCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Color.green)
                                )
                                .foregroundStyle(.white)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .help(gitStatus.aheadCount > 0 ? "Push \(gitStatus.aheadCount) commit(s) to remote" : "Push to remote")

                Divider()
                    .frame(height: 16)

                // Remote configuration button
                Button {
                    showingRemoteConfig = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .help("Remote Configuration")
                .popover(isPresented: $showingRemoteConfig, arrowEdge: .bottom) {
                    RemoteConfigurationPopover()
                }
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
        .alert(
            "Git \(gitService.lastError?.operation ?? "Operation") Failed",
            isPresented: Binding(
                get: { gitService.lastError != nil },
                set: { if !$0 { gitService.lastError = nil } }
            )
        ) {
            Button("OK") {
                gitService.lastError = nil
            }
        } message: {
            Text(gitService.lastError?.message ?? "Unknown error")
        }
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

// MARK: - Remote Configuration Popover

struct RemoteConfigurationPopover: View {
    @EnvironmentObject private var gitService: GitService

    @State private var showingAddRemote = false
    @State private var editingRemote: (name: String, url: String, isPush: Bool)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Remote Configuration")
                .font(.system(size: 13, weight: .semibold))
                .padding(.vertical, 10)

            Divider()

            if gitService.remotes.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No remotes configured")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 80)
            } else {
                // Table header
                HStack(spacing: 0) {
                    Text("Remote")
                        .frame(width: 70, alignment: .leading)
                    Text("URL")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Type")
                        .frame(width: 50, alignment: .leading)
                    Text("Action")
                        .frame(width: 50, alignment: .center)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                // Remote list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(gitService.remotes) { remote in
                            RemoteRowView(
                                remote: remote,
                                onEdit: { url, isPush in
                                    editingRemote = (remote.name, url, isPush)
                                },
                                onDelete: {
                                    gitService.deleteRemote(name: remote.name)
                                },
                                onFetch: {
                                    gitService.fetch()
                                }
                            )

                            if remote.id != gitService.remotes.last?.id {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            // Add remote button
            Button {
                showingAddRemote = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("Add Remote")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 420)
        .onAppear {
            Task {
                await gitService.loadRemotes()
            }
        }
        .sheet(isPresented: $showingAddRemote) {
            AddRemoteSheet { name, url in
                gitService.addRemote(name: name, url: url)
                showingAddRemote = false
            } onCancel: {
                showingAddRemote = false
            }
        }
        .sheet(
            item: Binding(
                get: {
                    if let editing = editingRemote {
                        return EditingRemote(name: editing.name, url: editing.url, isPush: editing.isPush)
                    }
                    return nil
                },
                set: { _ in editingRemote = nil }
            )
        ) { editing in
            EditRemoteURLSheet(
                remoteName: editing.name,
                currentURL: editing.url,
                isPushURL: editing.isPush
            ) { newURL in
                gitService.updateRemoteURL(name: editing.name, url: newURL, isPushURL: editing.isPush)
                editingRemote = nil
            } onCancel: {
                editingRemote = nil
            }
        }
    }
}

// Helper for sheet binding
private struct EditingRemote: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let isPush: Bool
}

// MARK: - Remote Row View

struct RemoteRowView: View {
    let remote: RemoteInfo
    let onEdit: (String, Bool) -> Void
    let onDelete: () -> Void
    let onFetch: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            // Fetch URL row
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(remote.name)
                        .font(.system(size: 12))
                }
                .frame(width: 70, alignment: .leading)

                Text(remote.fetchURL)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Fetch")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)

                HStack(spacing: 4) {
                    Button {
                        onFetch()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Fetch from remote")

                    Button {
                        onEdit(remote.fetchURL, false)
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Edit fetch URL")
                }
                .frame(width: 50)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            // Push URL row
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 70, alignment: .leading)

                Text(remote.pushURL)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Push")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)

                HStack(spacing: 4) {
                    Button {
                        onEdit(remote.pushURL, true)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Edit push URL")

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.8))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Delete remote")
                }
                .frame(width: 50)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .background(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Add Remote Sheet

struct AddRemoteSheet: View {
    let onCreate: (String, String) -> Void
    let onCancel: () -> Void

    @State private var remoteName = ""
    @State private var remoteURL = ""

    private var isValid: Bool {
        !remoteName.trimmingCharacters(in: .whitespaces).isEmpty
            && !remoteURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Remote")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("origin", text: $remoteName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("https://github.com/user/repo.git", text: $remoteURL)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    onCreate(
                        remoteName.trimmingCharacters(in: .whitespaces),
                        remoteURL.trimmingCharacters(in: .whitespaces)
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 350)
    }
}

// MARK: - Edit Remote URL Sheet

struct EditRemoteURLSheet: View {
    let remoteName: String
    let currentURL: String
    let isPushURL: Bool
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var newURL: String = ""

    private var isValid: Bool {
        !newURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit \(isPushURL ? "Push" : "Fetch") URL")
                .font(.headline)

            Text("Remote: \(remoteName)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("https://github.com/user/repo.git", text: $newURL)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave(newURL.trimmingCharacters(in: .whitespaces))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear {
            newURL = currentURL
        }
    }
}
