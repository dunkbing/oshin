//
//  GitGraphView.swift
//  oshin
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
        VStack(spacing: 0) {
            // Branch selector header
            BranchSelectorView()
                .environmentObject(gitService)

            Divider()

            // Graph content
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if gitService.branches.isEmpty {
                await gitService.loadBranches()
            }
            if gitService.commitLog.isEmpty {
                await gitService.loadCommitLog()
            }
        }
    }
}

// MARK: - Branch Selector View

struct BranchSelectorView: View {
    @EnvironmentObject private var gitService: GitService
    @State private var showRemoteBranches = true

    private var filteredBranches: [BranchInfo] {
        if showRemoteBranches {
            return gitService.branches
        } else {
            return gitService.branches.filter { !$0.isRemote }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Branch:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Picker(
                "",
                selection: Binding(
                    get: { gitService.selectedBranch },
                    set: { newValue in
                        Task {
                            await gitService.selectBranch(newValue)
                        }
                    }
                )
            ) {
                // Local branches section
                let localBranches = filteredBranches.filter { !$0.isRemote }
                if !localBranches.isEmpty {
                    ForEach(localBranches) { branch in
                        HStack {
                            if branch.isCurrent {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            Text(branch.name)
                        }
                        .tag(branch.name as String?)
                    }
                }

                // Remote branches section
                let remoteBranches = filteredBranches.filter { $0.isRemote }
                if showRemoteBranches && !remoteBranches.isEmpty {
                    Divider()
                    ForEach(remoteBranches) { branch in
                        Text(branch.name)
                            .foregroundStyle(.secondary)
                            .tag(branch.name as String?)
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 200)

            Toggle("Show Remote", isOn: $showRemoteBranches)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            Spacer()

            if let count = gitService.totalCommitCount {
                Text("\(count) commits")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Graph Content View

struct GitGraphContentView: View {
    let commits: [PositionedCommit]
    @Binding var selectedCommitId: String?
    let hasMore: Bool
    let isLoading: Bool
    let onLoadMore: () -> Void

    private let xSpacing: CGFloat = 16
    private let rowHeight: CGFloat = 28
    private let graphMinWidth: CGFloat = 80
    private let commitWidth: CGFloat = 70
    private let descriptionWidth: CGFloat = 320
    private let dateWidth: CGFloat = 140
    private let authorWidth: CGFloat = 160

    private var graphWidth: CGFloat {
        max(graphMinWidth, CGFloat((commits.map { $0.column }.max() ?? 0) + 1) * xSpacing + 16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("Graph")
                    .frame(width: graphWidth, alignment: .leading)
                Text("Commit")
                    .frame(width: commitWidth, alignment: .leading)
                Text("Description")
                    .frame(width: descriptionWidth, alignment: .leading)
                Text("Date")
                    .frame(width: dateWidth, alignment: .leading)
                Text("Author")
                    .frame(width: authorWidth, alignment: .leading)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .separatorColor).opacity(0.3))

            Divider()

            // Content
            ScrollView([.vertical]) {
                ZStack(alignment: .topLeading) {
                    // Draw connection lines (in graph column area)
                    ForEach(commits) { commit in
                        if let from = position(of: commit) {
                            ForEach(commit.commit.parentIds, id: \.self) { parentId in
                                if let parent = commits.first(where: { $0.id == parentId }),
                                    !parent.childrenIsHidden,
                                    let to = position(of: parent)
                                {
                                    GraphLine(
                                        from: from,
                                        to: to,
                                        fromColumn: commit.column,
                                        toColumn: parent.column
                                    )
                                }
                            }
                        }
                    }

                    // Rows with nodes and data
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(commits) { commit in
                            GraphRowView(
                                commit: commit,
                                selectedCommitId: $selectedCommitId,
                                graphWidth: graphWidth,
                                commitWidth: commitWidth,
                                descriptionWidth: descriptionWidth,
                                dateWidth: dateWidth,
                                authorWidth: authorWidth,
                                xSpacing: xSpacing,
                                rowHeight: rowHeight
                            )
                        }

                        // Load more button
                        if hasMore {
                            HStack {
                                Spacer()
                                    .frame(width: graphWidth)
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .padding(.vertical, 8)
                                } else {
                                    Button("Load More Commits...") {
                                        onLoadMore()
                                    }
                                    .buttonStyle(.link)
                                    .padding(.vertical, 8)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private let horizontalPadding: CGFloat = 12

    private func position(of commit: PositionedCommit) -> CGPoint? {
        // Account for row's horizontal padding + internal graph margin
        var point = CGPoint(
            x: horizontalPadding + CGFloat(commit.column) * xSpacing + 12 + GraphNodeView.nodeSize / 2,
            y: CGFloat(commit.row) * rowHeight + rowHeight / 2
        )
        if commit.childrenIsHidden {
            point.x += 0.5 * xSpacing
        }
        return point
    }
}

// MARK: - Graph Row View

struct GraphRowView: View {
    let commit: PositionedCommit
    @Binding var selectedCommitId: String?
    let graphWidth: CGFloat
    let commitWidth: CGFloat
    let descriptionWidth: CGFloat
    let dateWidth: CGFloat
    let authorWidth: CGFloat
    let xSpacing: CGFloat
    let rowHeight: CGFloat

    private var isSelected: Bool {
        commit.id == selectedCommitId
    }

    private var branchColor: Color {
        BranchColors.color(for: commit.column)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Graph column with node
            ZStack(alignment: .leading) {
                GraphNodeView(
                    commitId: commit.id,
                    column: commit.column,
                    selectedCommitId: $selectedCommitId
                )
                .offset(
                    x: CGFloat(commit.column) * xSpacing + 12 + (commit.childrenIsHidden ? 0.5 * xSpacing : 0),
                    y: 0
                )
            }
            .frame(width: graphWidth, height: rowHeight, alignment: .leading)

            // Commit hash
            Text(commit.commit.shortId)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(branchColor)
                .frame(width: commitWidth, alignment: .leading)

            // Description
            Text(commit.commit.summary)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: descriptionWidth, alignment: .leading)

            // Date
            Text(commit.commit.formattedDate)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: dateWidth, alignment: .leading)

            // Author
            Text(commit.commit.authorName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: authorWidth, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .background {
            if isSelected {
                branchColor.opacity(0.15)
            } else {
                Color.clear
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedCommitId = commit.id
        }
    }
}

// MARK: - Branch Colors

enum BranchColors {
    static let colors: [Color] = [
        Color(red: 0.35, green: 0.78, blue: 0.35),  // Green
        Color(red: 0.40, green: 0.60, blue: 0.95),  // Blue
        Color(red: 0.95, green: 0.45, blue: 0.65),  // Pink
        Color(red: 0.95, green: 0.75, blue: 0.30),  // Yellow/Orange
        Color(red: 0.70, green: 0.50, blue: 0.90),  // Purple
        Color(red: 0.40, green: 0.85, blue: 0.85),  // Cyan
        Color(red: 0.95, green: 0.55, blue: 0.35),  // Orange
        Color(red: 0.85, green: 0.45, blue: 0.85),  // Magenta
    ]

    static func color(for column: Int) -> Color {
        colors[column % colors.count]
    }
}

// MARK: - Graph Line

struct GraphLine: View {
    let from: CGPoint
    let to: CGPoint
    let fromColumn: Int
    let toColumn: Int

    private let lineWidth: CGFloat = 2

    var body: some View {
        Path { path in
            path.move(to: from)

            if fromColumn == toColumn {
                // Straight vertical line (same branch)
                path.addLine(to: to)
            } else {
                // Curved line for branch/merge
                let curveRadius: CGFloat = 12
                let midY = from.y + (to.y - from.y) * 0.5

                if to.x > from.x {
                    // Curving right (branching out)
                    path.addLine(to: CGPoint(x: from.x, y: midY - curveRadius))
                    path.addQuadCurve(
                        to: CGPoint(x: from.x + curveRadius, y: midY),
                        control: CGPoint(x: from.x, y: midY)
                    )
                    path.addLine(to: CGPoint(x: to.x - curveRadius, y: midY))
                    path.addQuadCurve(
                        to: CGPoint(x: to.x, y: midY + curveRadius),
                        control: CGPoint(x: to.x, y: midY)
                    )
                    path.addLine(to: to)
                } else {
                    // Curving left (merging in)
                    path.addLine(to: CGPoint(x: from.x, y: midY - curveRadius))
                    path.addQuadCurve(
                        to: CGPoint(x: from.x - curveRadius, y: midY),
                        control: CGPoint(x: from.x, y: midY)
                    )
                    path.addLine(to: CGPoint(x: to.x + curveRadius, y: midY))
                    path.addQuadCurve(
                        to: CGPoint(x: to.x, y: midY + curveRadius),
                        control: CGPoint(x: to.x, y: midY)
                    )
                    path.addLine(to: to)
                }
            }
        }
        .stroke(BranchColors.color(for: toColumn), lineWidth: lineWidth)
    }
}

// MARK: - Graph Node View

struct GraphNodeView: View {
    static let nodeSize: CGFloat = 8
    static let selectedNodeSize: CGFloat = 10

    let commitId: String
    let column: Int
    @Binding var selectedCommitId: String?

    private var isSelected: Bool {
        commitId == selectedCommitId
    }

    private var branchColor: Color {
        BranchColors.color(for: column)
    }

    var body: some View {
        Circle()
            .fill(branchColor)
            .overlay(
                Circle()
                    .stroke(Color(nsColor: .textBackgroundColor), lineWidth: 2)
            )
            .frame(
                width: isSelected ? Self.selectedNodeSize : Self.nodeSize,
                height: isSelected ? Self.selectedNodeSize : Self.nodeSize
            )
            .shadow(color: isSelected ? branchColor.opacity(0.6) : .clear, radius: 3)
    }
}
