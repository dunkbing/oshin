//
//  GitLogView.swift
//  agentmonitor
//
//  Git commit history view
//

import SwiftUI

struct GitLogView: View {
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
                List(
                    selection: Binding(
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
                    )
                ) {
                    ForEach(gitService.commitLog) { commit in
                        CommitRowView(
                            commit: commit,
                            isSelected: gitService.selectedCommitId == commit.id
                        )
                        .tag(commit.id)
                        .onAppear {
                            // Load more when reaching the end
                            if commit.id == gitService.commitLog.last?.id {
                                Task {
                                    await gitService.loadMoreCommits()
                                }
                            }
                        }
                    }

                    if gitService.hasMoreCommits {
                        HStack {
                            Spacer()
                            if gitService.isLoadingLog {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Button("Load More") {
                                    Task {
                                        await gitService.loadMoreCommits()
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.plain)
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

// MARK: - Commit Row View

struct CommitRowView: View {
    let commit: CommitInfo
    var isSelected: Bool = false

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Summary line
            HStack(alignment: .firstTextBaseline) {
                Text(commit.summary)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer()

                Text(commit.shortId)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.orange : Color.gray)
            }

            // Author and date
            HStack(spacing: 6) {
                // Author avatar
                AuthorAvatarView(initial: commit.authorInitial, size: 16)

                Text(commit.authorName)
                    .font(.system(size: 11))

                Spacer()

                Text(commit.relativeDate)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Author Avatar View

struct AuthorAvatarView: View {
    let initial: String
    let size: CGFloat

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.6, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(avatarColor)
            )
    }

    private var avatarColor: Color {
        // Generate a consistent color based on the initial
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo]
        let index = abs(initial.hashValue) % colors.count
        return colors[index]
    }
}
