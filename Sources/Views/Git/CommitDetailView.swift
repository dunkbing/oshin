//
//  CommitDetailView.swift
//  agentmonitor
//
//  View for displaying commit details with file changes and diffs
//

import SwiftUI

struct CommitDetailView: View {
    @EnvironmentObject private var gitService: GitService

    let fontSize: Double

    @State private var expandedFiles: Set<String> = []
    @AppStorage("diffViewMode") private var viewMode: DiffViewMode = .unified

    private var detail: CommitDetail? { gitService.selectedCommitDetail }

    var body: some View {
        if gitService.isLoadingCommitDetail {
            ProgressView("Loading commit...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail = detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Commit header
                    CommitHeaderSection(commit: detail.commit)

                    Divider()

                    // Stats
                    CommitStatsFooter(
                        fileCount: detail.files.count,
                        additions: detail.totalAdditions,
                        deletions: detail.totalDeletions
                    )

                    Divider()

                    // Files header with view mode toggle
                    CommitFilesHeader(
                        fileCount: detail.files.count,
                        viewMode: $viewMode
                    )

                    Divider()

                    // File changes
                    CommitFilesSection(
                        files: detail.files,
                        expandedFiles: $expandedFiles,
                        fontSize: fontSize,
                        viewMode: viewMode
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No Commit Selected",
                systemImage: "clock.arrow.circlepath",
                description: Text("Select a commit to view its details.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Commit Header Section

struct CommitHeaderSection: View {
    let commit: CommitInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Commit hashes
            HStack(spacing: 8) {
                Text(commit.shortId)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.orange)

                if let parentId = commit.parentIds.first {
                    Text("\u{2190}")
                        .foregroundStyle(.secondary)
                    Text(String(parentId.prefix(7)))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Commit message
            Text(commit.summary)
                .font(.system(size: 16, weight: .semibold))

            if let body = commit.body, !body.isEmpty {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Author info
            HStack(spacing: 10) {
                AuthorAvatarView(initial: commit.authorInitial, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(commit.authorName)
                            .font(.system(size: 13, weight: .medium))
                        Text(commit.authorEmail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(commit.formattedDate)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

// MARK: - Commit Files Header

struct CommitFilesHeader: View {
    let fileCount: Int
    @Binding var viewMode: DiffViewMode

    var body: some View {
        HStack {
            Text("\(fileCount) file\(fileCount == 1 ? "" : "s") changed")
                .font(.system(size: 12, weight: .medium))

            Spacer()

            // View mode toggle
            Picker("", selection: $viewMode) {
                ForEach(DiffViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 70)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Commit Files Section

struct CommitFilesSection: View {
    let files: [CommitFileChange]
    @Binding var expandedFiles: Set<String>
    let fontSize: Double
    let viewMode: DiffViewMode

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(files) { file in
                CommitFileRow(
                    file: file,
                    isExpanded: expandedFiles.contains(file.id),
                    fontSize: fontSize,
                    viewMode: viewMode,
                    onToggle: {
                        if expandedFiles.contains(file.id) {
                            expandedFiles.remove(file.id)
                        } else {
                            expandedFiles.insert(file.id)
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Commit File Row

struct CommitFileRow: View {
    let file: CommitFileChange
    let isExpanded: Bool
    let fontSize: Double
    let viewMode: DiffViewMode
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text(file.path)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    // Change type badge
                    Text(file.changeType.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(file.changeType.color, in: RoundedRectangle(cornerRadius: 3))

                    // Stats
                    if file.additions > 0 {
                        Text("+\(file.additions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    if file.deletions > 0 {
                        Text("-\(file.deletions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.02))

            // Expanded diff content
            if isExpanded && !file.diffOutput.isEmpty {
                CommitFileDiffView(diffOutput: file.diffOutput, fontSize: fontSize, viewMode: viewMode)
            }

            Divider()
        }
    }
}

// MARK: - Commit File Diff View

struct CommitFileDiffView: View {
    let diffOutput: String
    let fontSize: Double
    let viewMode: DiffViewMode

    @State private var lines: [DiffLine] = []

    var body: some View {
        Group {
            switch viewMode {
            case .unified:
                UnifiedDiffView(lines: lines, fontSize: fontSize)
            case .split:
                SplitDiffView(lines: lines, fontSize: fontSize)
            }
        }
        .onAppear {
            parseLines()
        }
        .onChange(of: diffOutput) { _, _ in
            parseLines()
        }
    }

    private func parseLines() {
        guard !diffOutput.isEmpty else {
            lines = []
            return
        }

        let parser = DiffLineParser(diffOutput: diffOutput)
        lines = parser.parseAll()
    }
}

// MARK: - Commit Stats Footer

struct CommitStatsFooter: View {
    let fileCount: Int
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack {
            Spacer()

            Text("\(fileCount) file\(fileCount == 1 ? "" : "s") changed")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if additions > 0 {
                Text(", \(additions) insertion\(additions == 1 ? "" : "s")(+)")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }

            if deletions > 0 {
                Text(", \(deletions) deletion\(deletions == 1 ? "" : "s")(-)")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(12)
    }
}
