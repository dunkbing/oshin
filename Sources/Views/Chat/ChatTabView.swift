//
//  ChatTabView.swift
//  agentmonitor
//
//  Chat interface for AI agents with ACP integration
//

import SwiftUI

struct ChatTabView: View {
    let repositoryPath: String

    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"

    @StateObject private var session: AgentSession
    @State private var inputText: String = ""
    @State private var selectedAgentId: String
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isInitializing: Bool = false

    init(repositoryPath: String) {
        self.repositoryPath = repositoryPath
        let defaultAgent = UserDefaults.standard.string(forKey: "defaultACPAgent") ?? "claude"
        _selectedAgentId = State(initialValue: defaultAgent)
        _session = StateObject(wrappedValue: AgentSession(agentName: defaultAgent))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with agent selector
            headerSection

            Divider()

            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.messages) { message in
                            MessageRowView(message: message)
                                .id(message.id)
                        }

                        if session.isStreaming, let thought = session.currentThought {
                            ThoughtBubbleView(thought: thought)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: session.messages.count) { _, _ in
                    if let lastMessage = session.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Input section
            inputSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await startSession()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onDisappear {
            Task {
                await session.close()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 12) {
            // Agent selector
            Menu {
                ForEach(AgentRegistry.shared.getEnabledAgents(), id: \.id) { agent in
                    Button {
                        switchAgent(to: agent.id)
                    } label: {
                        HStack {
                            Text(agent.name)
                            if agent.id == selectedAgentId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let metadata = AgentRegistry.shared.getMetadata(for: selectedAgentId) {
                        AgentIconView(iconType: metadata.iconType, size: 16)
                    }
                    Text(selectedAgentName)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Status indicator
            statusIndicator

            Spacer()

            // Config options (if available)
            if !session.configOptions.isEmpty {
                configOptionsMenu
            }

            // Stop button when streaming
            if session.isStreaming {
                Button {
                    Task {
                        await session.cancelCurrentPrompt()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var selectedAgentName: String {
        AgentRegistry.shared.getMetadata(for: selectedAgentId)?.name ?? selectedAgentId
    }

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            switch session.sessionState {
            case .idle:
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
                Text("Idle")
            case .initializing:
                ProgressView()
                    .scaleEffect(0.6)
                Text("Connecting...")
            case .ready:
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Ready")
            case .error(let message):
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text(message)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var configOptionsMenu: some View {
        ForEach(Array(session.configOptions.enumerated()), id: \.element.id.value) { _, option in
            ConfigOptionMenuView(option: option, session: session)
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        HStack(spacing: 12) {
            // Text input row
            HStack(spacing: 10) {
                // Attachment button
                Button {
                    // TODO: Attach file
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                // Text field
                TextField("Ask anything...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .onSubmit {
                        if !inputText.isEmpty && !session.isStreaming {
                            sendMessage()
                        }
                    }

                // Send button
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: session.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !session.isStreaming)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var canSend: Bool {
        !inputText.isEmpty && session.sessionState.isReady && !session.isStreaming
    }

    // MARK: - Actions

    private func startSession() async {
        guard !session.isActive else { return }
        isInitializing = true
        do {
            try await session.start(workingDirectory: repositoryPath)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isInitializing = false
    }

    private func switchAgent(to agentId: String) {
        guard agentId != selectedAgentId else { return }
        selectedAgentId = agentId

        Task {
            await session.close()
            // Create new session with different agent would require recreating the view
            // For now, just restart with same session object after updating agent name
        }
    }

    private func sendMessage() {
        guard canSend else { return }
        let message = inputText
        inputText = ""

        Task {
            do {
                try await session.sendMessage(content: message)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

// MARK: - Config Option Menu View

struct ConfigOptionMenuView: View {
    let option: SessionConfigOption
    let session: AgentSession

    private var selectData: (options: [SessionConfigSelectOption], currentValue: SessionConfigValueId)? {
        guard case .select(let select) = option.kind else { return nil }
        switch select.options {
        case .ungrouped(let options):
            return (options, select.currentValue)
        case .grouped(let groups):
            let allOptions = groups.flatMap { $0.options }
            return (allOptions, select.currentValue)
        }
    }

    var body: some View {
        if let data = selectData {
            Menu {
                ForEach(Array(data.options.enumerated()), id: \.offset) { _, selectOption in
                    Button {
                        Task {
                            try? await session.setConfigOption(
                                configId: option.id,
                                value: selectOption.value
                            )
                        }
                    } label: {
                        HStack {
                            Text(selectOption.name)
                            if selectOption.value.value == data.currentValue.value {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(option.name)
                    if let selected = data.options.first(where: { $0.value.value == data.currentValue.value }) {
                        Text(selected.name)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .font(.system(size: 11))
                .foregroundStyle(.primary)
            }
            .menuStyle(.borderlessButton)
        }
    }
}

// MARK: - Message Row View

struct MessageRowView: View {
    let message: MessageItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Message header
            HStack {
                Text(message.role == .user ? "You" : message.role == .agent ? "Agent" : "System")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(message.role == .user ? .blue : .primary)

                Spacer()

                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // Message content
            if !message.content.isEmpty {
                Text(message.content)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
            }

            // Tool calls
            ForEach(message.toolCalls, id: \.toolCallId) { toolCall in
                ToolCallView(toolCall: toolCall)
            }

            // Execution time for completed agent messages
            if message.role == .agent, message.isComplete, let time = message.executionTime {
                Text(String(format: "%.1fs", time))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? Color.blue.opacity(0.05) : Color.clear)
    }
}

// MARK: - Tool Call View

struct ToolCallView: View {
    let toolCall: ToolCall

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tool call header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                        .font(.system(size: 12))

                    Text(toolCall.title.isEmpty ? (toolCall.kind?.rawValue ?? "Tool Call") : toolCall.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    // Location info
                    if let locations = toolCall.locations, !locations.isEmpty {
                        ForEach(Array(locations.enumerated()), id: \.offset) { _, location in
                            if let path = location.path {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc")
                                        .font(.system(size: 10))
                                    Text(path)
                                    if let line = location.line {
                                        Text(":\(line)")
                                    }
                                }
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Content blocks
                    ForEach(Array(toolCall.content.enumerated()), id: \.offset) { _, content in
                        ToolCallContentView(content: content)
                    }

                    // Raw input/output
                    if let rawInput = toolCall.rawInput {
                        DisclosureGroup("Input") {
                            Text(formatJSON(rawInput))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .font(.system(size: 11))
                    }

                    if let rawOutput = toolCall.rawOutput {
                        DisclosureGroup("Output") {
                            Text(formatJSON(rawOutput))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .font(.system(size: 11))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    private var statusIcon: String {
        switch toolCall.status {
        case .pending:
            return "circle.dashed"
        case .inProgress:
            return "circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch toolCall.status {
        case .pending:
            return .gray
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private func formatJSON(_ codable: AnyCodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(codable),
            let string = String(data: data, encoding: .utf8)
        {
            return string
        }
        return String(describing: codable)
    }
}

// MARK: - Tool Call Content View

struct ToolCallContentView: View {
    let content: ToolCallContent

    var body: some View {
        switch content {
        case .content(let block):
            ContentBlockView(block: block)
        case .diff(let diff):
            VStack(alignment: .leading, spacing: 4) {
                Text("File: \(diff.path)")
                    .font(.system(size: 11, weight: .medium))
                if let oldText = diff.oldText {
                    Text(oldText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                Text(diff.newText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
            }
        case .terminal(let terminal):
            HStack(spacing: 4) {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                Text("Terminal: \(terminal.terminalId)")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Content Block View

struct ContentBlockView: View {
    let block: ContentBlock

    var body: some View {
        switch block {
        case .text(let textContent):
            Text(textContent.text)
                .font(.system(size: 12))
                .textSelection(.enabled)
        case .image:
            Text("[Image]")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .audio:
            Text("[Audio]")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .resource:
            Text("[Resource]")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .resourceLink(let link):
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 10))
                Text(link.title ?? link.name)
            }
            .font(.system(size: 12))
            .foregroundStyle(.blue)
        }
    }
}

// MARK: - Thought Bubble View

struct ThoughtBubbleView: View {
    let thought: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "brain")
                    .font(.system(size: 11))
                Text("Thinking...")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.purple)

            Text(thought)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.05))
    }
}
