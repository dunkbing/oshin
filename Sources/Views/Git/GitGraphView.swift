//
//  GitGraphView.swift
//  agentmonitor
//
//  Git commit graph visualization
//

import SwiftUI

// MARK: - Positioned Commit

struct PositionedCommit: Identifiable {
    var id: String { commit.id }
    let commit: CommitInfo
    let column: Int
    let row: Int
    var childrenIsHidden: Bool = false
}

// MARK: - Commit Graph Algorithm

struct CommitGraph {
    private func makeColumn(childColumn: Int, usingColumn: [Int]) -> Int {
        var col = childColumn + 1
        while usingColumn.contains(col) {
            col += 1
        }
        return col
    }

    func positionedCommits(_ commits: [CommitInfo]) -> [PositionedCommit] {
        var result: [PositionedCommit] = []
        var usingColumns: [Int] = []

        for (row, commit) in commits.enumerated() {
            if row == 0 {
                // First commit gets column 0
                result.append(PositionedCommit(commit: commit, column: 0, row: row))
                usingColumns.append(0)
            } else {
                // Find children (commits that have this commit as a parent)
                let children = result.filter { $0.commit.parentIds.contains(commit.id) }

                if children.isEmpty {
                    // No children found (e.g., filtered search results)
                    let positioned = PositionedCommit(
                        commit: commit,
                        column: result[row - 1].column,
                        row: row,
                        childrenIsHidden: true
                    )
                    result.append(positioned)
                } else {
                    let positioned: PositionedCommit

                    // Check if this commit is a first parent of any child
                    if let childColumn =
                        children
                        .filter({ $0.commit.parentIds.first == commit.id })
                        .map({ $0.column })
                        .min()
                    {
                        // Inherit child's column (no new column needed)
                        positioned = PositionedCommit(commit: commit, column: childColumn, row: row)
                    } else {
                        // Need a new column (merge commit's second parent)
                        let newColumn = makeColumn(childColumn: children[0].column, usingColumn: usingColumns)
                        positioned = PositionedCommit(commit: commit, column: newColumn, row: row)
                        usingColumns.append(newColumn)
                    }

                    result.append(positioned)

                    // Release columns that are no longer needed
                    for child in children {
                        // If child has only one parent and we're not continuing on that column
                        if child.column != positioned.column && child.commit.parentIds.count == 1 {
                            if let index = usingColumns.firstIndex(of: child.column) {
                                usingColumns.remove(at: index)
                            }
                        }
                    }
                }
            }
        }

        return result
    }
}

// MARK: - Git Graph View

struct GitGraphView: View {
    @EnvironmentObject private var gitService: GitService

    var body: some View {
        Group {
            if gitService.commitLog.isEmpty && gitService.isLoadingLog {
                ProgressView("Loading commits...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if gitService.commitLog.isEmpty {
                ContentUnavailableView(
                    "No Commits",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("No commit history found.")
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    GitGraphContentView(
                        commits: CommitGraph().positionedCommits(gitService.commitLog),
                        selectedCommitId: Binding(
                            get: { gitService.selectedCommitId },
                            set: { newValue in
                                if let commitId = newValue {
                                    Task {
                                        await gitService.loadCommitDetail(for: commitId)
                                    }
                                } else {
                                    gitService.clearSelectedCommit()
                                }
                            }
                        ),
                        hasMore: gitService.hasMoreCommits,
                        isLoading: gitService.isLoadingLog,
                        onLoadMore: {
                            Task {
                                await gitService.loadMoreCommits()
                            }
                        }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if gitService.commitLog.isEmpty {
                await gitService.loadCommitLog()
            }
        }
    }
}

// MARK: - Graph Content View

struct GitGraphContentView: View {
    let commits: [PositionedCommit]
    @Binding var selectedCommitId: String?
    let hasMore: Bool
    let isLoading: Bool
    let onLoadMore: () -> Void

    private let xSpacing: CGFloat = 20
    private let ySpacing: CGFloat = 48
    private let textWidth: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Draw connection lines first (below nodes)
                ForEach(commits) { commit in
                    if let from = position(of: commit) {
                        ForEach(commit.commit.parentIds, id: \.self) { parentId in
                            if let parent = commits.first(where: { $0.id == parentId }),
                                !parent.childrenIsHidden,
                                let to = position(of: parent)
                            {
                                GraphLine(from: from, to: to)
                            }
                        }
                    }
                }

                // Draw nodes and labels
                ForEach(commits) { commit in
                    if let point = position(of: commit) {
                        // Node
                        GraphNodeView(
                            commitId: commit.id,
                            selectedCommitId: $selectedCommitId
                        )
                        .position(point)

                        // Text label
                        GraphNodeTextView(
                            commitId: commit.id,
                            title: commit.commit.summary,
                            shortId: commit.commit.shortId,
                            selectedCommitId: $selectedCommitId
                        )
                        .frame(width: textWidth, alignment: .leading)
                        .offset(x: textWidth / 2 + 12, y: 0)
                        .position(point)
                    }
                }
            }
            .frame(
                width: CGFloat((commits.map { $0.column }.max() ?? 0)) * xSpacing + textWidth + 24,
                height: CGFloat(commits.count) * ySpacing
            )

            // Load more button
            if hasMore {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Button("Load More") {
                            onLoadMore()
                        }
                        .buttonStyle(.link)
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
    }

    private func position(of commit: PositionedCommit) -> CGPoint? {
        var point = CGPoint(
            x: CGFloat(commit.column) * xSpacing + GraphNodeView.nodeSize / 2,
            y: CGFloat(commit.row) * ySpacing + GraphNodeView.nodeSize / 2
        )
        if commit.childrenIsHidden {
            point.x += 0.5 * xSpacing
        }
        return point
    }
}

// MARK: - Graph Line

struct GraphLine: View {
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
    }
}

// MARK: - Graph Node View

struct GraphNodeView: View {
    static let nodeSize: CGFloat = 12
    static let selectedNodeSize: CGFloat = 16

    let commitId: String
    @Binding var selectedCommitId: String?

    private var isSelected: Bool {
        commitId == selectedCommitId
    }

    private var fillColor: Color {
        isSelected ? Color.accentColor : Color.primary.opacity(0.8)
    }

    var body: some View {
        Circle()
            .fill(fillColor)
            .overlay(
                Circle()
                    .stroke(Color(nsColor: .textBackgroundColor), lineWidth: 2)
            )
            .frame(
                width: isSelected ? Self.selectedNodeSize : Self.nodeSize,
                height: isSelected ? Self.selectedNodeSize : Self.nodeSize
            )
            .onTapGesture {
                selectedCommitId = commitId
            }
    }
}

// MARK: - Graph Node Text View

struct GraphNodeTextView: View {
    let commitId: String
    let title: String
    let shortId: String
    @Binding var selectedCommitId: String?

    private var isSelected: Bool {
        commitId == selectedCommitId
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(shortId)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(isSelected ? .orange : .secondary)

            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.15))
            }
        }
        .onTapGesture {
            selectedCommitId = commitId
        }
    }
}
