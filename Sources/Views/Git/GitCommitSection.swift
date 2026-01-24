//
//  GitCommitSection.swift
//  agentmonitor
//
//  Commit message input and button
//

import SwiftUI

struct GitCommitSection: View {
    let gitStatus: GitStatus
    let isOperationPending: Bool
    @Binding var commitMessage: String
    let onCommit: (String) -> Void
    let onStageAll: (@escaping @Sendable () -> Void) -> Void

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
                onCommit(commitMessage)
                commitMessage = ""
            } label: {
                Text("Commit")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .background(commitButtonEnabled ? Color.accentColor : Color.gray.opacity(0.3))
            .foregroundColor(commitButtonEnabled ? .white : .gray)
            .disabled(!commitButtonEnabled)

            // Divider
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 32)

            // Dropdown menu
            Menu {
                Button("Commit All") {
                    commitAllAction()
                }
                .disabled(commitMessage.isEmpty || isOperationPending)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(commitButtonEnabled ? .white : .gray)
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
            .menuIndicator(.hidden)
            .background(commitButtonEnabled ? Color.accentColor : Color.gray.opacity(0.3))
            .disabled(!commitButtonEnabled && commitMessage.isEmpty)
        }
        .fixedSize(horizontal: false, vertical: true)
        .cornerRadius(6)
    }

    private var commitButtonEnabled: Bool {
        !commitMessage.isEmpty && !gitStatus.stagedFiles.isEmpty && !isOperationPending
    }

    private func commitAllAction() {
        let message = commitMessage
        let commit = onCommit

        onStageAll { @Sendable in
            Task { @MainActor in
                commit(message)
            }
        }
        commitMessage = ""
    }
}
