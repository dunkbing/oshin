//
//  GitFileListView.swift
//  agentmonitor
//
//  File list with staging controls
//

import SwiftUI

struct GitFileListView: View {
    let gitStatus: GitStatus
    let isOperationPending: Bool
    let selectedFile: String?
    let onStageFile: (String) -> Void
    let onUnstageFile: (String) -> Void
    let onFileClick: (String) -> Void

    var body: some View {
        ScrollView {
            if gitStatus.stagedFiles.isEmpty && gitStatus.modifiedFiles.isEmpty && gitStatus.untrackedFiles.isEmpty {
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
        let allFiles = Set(gitStatus.stagedFiles + gitStatus.modifiedFiles + gitStatus.untrackedFiles)

        ForEach(Array(allFiles).sorted(), id: \.self) { file in
            let isStaged = gitStatus.stagedFiles.contains(file)
            let isModified = gitStatus.modifiedFiles.contains(file)
            let isUntracked = gitStatus.untrackedFiles.contains(file)

            if isStaged && isModified {
                // Mixed state
                fileRow(file: file, isStaged: nil, statusColor: .orange, statusIcon: "circle.lefthalf.filled")
            } else if isStaged {
                fileRow(file: file, isStaged: true, statusColor: .green, statusIcon: "checkmark.circle.fill")
            } else if isModified {
                fileRow(file: file, isStaged: false, statusColor: .orange, statusIcon: "circle.fill")
            } else if isUntracked {
                fileRow(file: file, isStaged: false, statusColor: .blue, statusIcon: "circle.fill")
            }
        }
    }

    private func fileRow(file: String, isStaged: Bool?, statusColor: Color, statusIcon: String) -> some View {
        rowContainer(file: file) {
            HStack(spacing: 8) {
                if let staged = isStaged {
                    Toggle(
                        isOn: Binding(
                            get: { staged },
                            set: { newValue in
                                if newValue {
                                    onStageFile(file)
                                } else {
                                    onUnstageFile(file)
                                }
                            }
                        )
                    ) {
                        EmptyView()
                    }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(isOperationPending)
                } else {
                    Button {
                        onStageFile(file)
                    } label: {
                        Image(systemName: "minus.square")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isOperationPending)
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
        }
    }

    private func conflictRow(file: String) -> some View {
        rowContainer(file: file, leadingPadding: 8) {
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
        }
    }

    private func rowContainer<Content: View>(
        file: String,
        leadingPadding: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .contentShape(Rectangle())
            .onTapGesture {
                onFileClick(file)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .padding(.leading, leadingPadding)
            .background(selectedFile == file ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
    }
}
