//
//  ChatTabView.swift
//  agentmonitor
//
//  Chat interface for AI agents
//

import SwiftUI

struct ChatTabView: View {
    let repositoryPath: String

    @State private var inputText: String = ""
    @State private var selectedAgent: String = "Agent"
    @State private var selectedModel: String = "claude-sonnet-4-20250514"

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollView {
                VStack(spacing: 8) {
                    // Session header
                    sessionHeader
                        .padding(.top, 20)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Input section
            inputSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session Header

    private var sessionHeader: some View {
        VStack(spacing: 8) {
            Text("Session started with \(selectedAgent) in \(repositoryPath)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        HStack(spacing: 12) {
            // Agent dropdown
            Menu {
                Button("Claude") { selectedAgent = "Claude" }
                Button("Codex") { selectedAgent = "Codex" }
                Button("Gemini") { selectedAgent = "Gemini" }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                    Text(selectedAgent)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Text input row
            HStack(spacing: 10) {
                // Attachment button
                Button {
                    // Attach file
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                // Text field
                TextField("Ask anything...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))

                // Model selector
                Menu {
                    Button("claude-sonnet-4-20250514") { selectedModel = "claude-sonnet-4-20250514" }
                    Button("claude-opus-4-20250514") { selectedModel = "claude-opus-4-20250514" }
                    Button("gpt-5.2-codex (medium)") { selectedModel = "gpt-5.2-codex (medium)" }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.hexagongrid")
                            .font(.system(size: 12))
                        Text(selectedModel)
                            .font(.system(size: 11))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)

                // Mic button
                Button {
                    // Voice input
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                // Send button
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        // TODO: Send message to agent
        inputText = ""
    }
}
