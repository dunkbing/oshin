//
//  GitFileListView.swift
//  agentmonitor
//
//  File list with staging controls
//

import SwiftUI

// MARK: - File Row View

struct FileRowView: View {
    @EnvironmentObject private var gitService: GitService

    let file: String
    let isSelected: Bool
    let onFileClick: (String) -> Void

    private var gitStatus: GitStatus { gitService.currentStatus }
    private var isStaged: Bool { gitStatus.stagedFiles.contains(file) }
    private var isModified: Bool { gitStatus.modifiedFiles.contains(file) }
    private var isDeleted: Bool { gitStatus.deletedFiles.contains(file) }
    private var isUntracked: Bool { gitStatus.untrackedFiles.contains(file) }

    private var isMixedState: Bool { isStaged && (isModified || isDeleted) }

    private var statusColor: Color {
        if isMixedState { return .orange }
        if isStaged { return .green }
        if isDeleted { return .red }
        if isModified { return .orange }
        if isUntracked { return .blue }
        return .secondary
    }

    private var statusIcon: String {
        if isMixedState { return "circle.lefthalf.filled" }
        if isStaged { return "checkmark.circle.fill" }
        if isDeleted { return "minus.circle.fill" }
        return "circle.fill"
    }

    var body: some View {
        HStack(spacing: 8) {
            if isMixedState {
                Button {
                    gitService.stageFile(file)
                } label: {
                    Image(systemName: "minus.square")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(gitService.isOperationPending)
            } else {
                Toggle(
                    isOn: Binding(
                        get: { isStaged },
                        set: { newValue in
                            if newValue {
                                gitService.stageFile(file)
                            } else {
                                gitService.unstageFile(file)
                            }
                        }
                    )
                ) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(gitService.isOperationPending)
            }

            Image(systemName: statusIcon)
                .font(.system(size: 8))
                .foregroundStyle(statusColor)

            Text(file)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onFileClick(file)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }
}

// MARK: - Git File List View

struct GitFileListView: View {
    @EnvironmentObject private var gitService: GitService

    let selectedFile: String?
    let onFileClick: (String) -> Void

    private var gitStatus: GitStatus { gitService.currentStatus }

    var body: some View {
        ScrollView {
            if gitStatus.stagedFiles.isEmpty && gitStatus.modifiedFiles.isEmpty && gitStatus.deletedFiles.isEmpty
                && gitStatus.untrackedFiles.isEmpty
            {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    fileListContent
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.none, value: gitStatus)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Changes")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 200)
    }

    @ViewBuilder
    private var fileListContent: some View {
        // Conflicted files
        if !gitStatus.conflictedFiles.isEmpty {
            ForEach(gitStatus.conflictedFiles, id: \.self) { file in
                conflictRow(file: file)
            }
        }

        // Get all unique files
        let allFiles = Set(
            gitStatus.stagedFiles + gitStatus.modifiedFiles + gitStatus.deletedFiles + gitStatus.untrackedFiles)

        ForEach(Array(allFiles).sorted(), id: \.self) { file in
            FileRowView(
                file: file,
                isSelected: selectedFile == file,
                onFileClick: onFileClick
            )
            .id(file)
        }
    }

    private func conflictRow(file: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .frame(width: 14)

            Text(file)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onFileClick(file)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .padding(.leading, 8)
        .background(selectedFile == file ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }
}
