//
//  GitCommitSection.swift
//  oshin
//
//  Commit message input and button
//

import SwiftUI

struct GitCommitSection: View {
    @EnvironmentObject private var gitService: GitService
    @Binding var commitMessage: String

    var body: some View {
        VStack(spacing: 8) {
            // Commit message
            ZStack(alignment: .topLeading) {
                if commitMessage.isEmpty {
                    Text("Enter commit message")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $commitMessage)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(height: 80)
                    .padding(4)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
            )

            // Commit button menu
            commitButtonMenu
        }
    }

    private var commitButtonMenu: some View {
        HStack(spacing: 0) {
            // Main commit button
            Button {
                gitService.commit(message: commitMessage)
                commitMessage = ""
            } label: {
                Text("Commit")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .buttonStyle(.plain)
            .foregroundColor(commitButtonEnabled ? .white : .secondary)
            .disabled(!commitButtonEnabled)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 16)

            // Dropdown menu
            Menu {
                Button("Commit All") {
                    commitAllAction()
                }
                .disabled(commitMessage.isEmpty || gitService.isOperationPending)

                Divider()

                Button("Amend Last Commit") {
                    gitService.amendCommit(message: commitMessage.isEmpty ? nil : commitMessage)
                    commitMessage = ""
                }
                .disabled(gitService.isOperationPending)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(commitButtonEnabled ? .white : .secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 32, height: 28)
            .fixedSize()
            .disabled(!commitButtonEnabled && commitMessage.isEmpty)
        }
        .frame(height: 28)
        .background(commitButtonEnabled ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var commitButtonEnabled: Bool {
        !commitMessage.isEmpty && !gitService.currentStatus.stagedFiles.isEmpty && !gitService.isOperationPending
    }

    private func commitAllAction() {
        let message = commitMessage
        gitService.stageAll { @Sendable [weak gitService] in
            Task { @MainActor in
                gitService?.commit(message: message)
            }
        }
        commitMessage = ""
    }
}
