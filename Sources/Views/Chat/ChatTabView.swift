//
//  ChatTabView.swift
//  oshin
//
//  Chat interface for AI agents with ACP integration
//

import SwiftUI

struct ChatTabView: View {
    let chatSession: ChatSession
    let sessionManager: ChatSessionManager
    let isSelected: Bool

    @StateObject private var agentSession: AgentSession
    @State private var inputText: String = ""
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isInitializing: Bool = false
    @FocusState private var isInputFocused: Bool

    init(chatSession: ChatSession, sessionManager: ChatSessionManager, isSelected: Bool) {
        self.chatSession = chatSession
        self.sessionManager = sessionManager
        self.isSelected = isSelected

        // Get or create agent session
        if let existing = sessionManager.getAgentSession(for: chatSession.id) {
            _agentSession = StateObject(wrappedValue: existing)
        } else {
            let newSession = AgentSession(agentName: chatSession.agentId)
            _agentSession = StateObject(wrappedValue: newSession)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(agentSession.messages) { message in
                            MessageRowView(message: message, agentName: chatSession.agentId)
                                .id(message.id)
                        }

                        if agentSession.isStreaming, let thought = agentSession.currentThought {
                            ThoughtBubbleView(thought: thought)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: agentSession.messages.count) { _, _ in
                    if let lastMessage = agentSession.messages.last {
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
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
        .onAppear {
            if isSelected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
    }

    // MARK: - Input Toolbar

    private var inputToolbar: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIndicator

            Spacer()

            // Config options (if available)
            if !agentSession.configOptions.isEmpty {
                configOptionsMenu
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            switch agentSession.sessionState {
            case .idle:
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
                Text("Idle")
            case .installing(let message):
                ProgressView()
                    .scaleEffect(0.6)
                Text(message)
                    .lineLimit(1)
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
        ForEach(Array(agentSession.configOptions.enumerated()), id: \.element.id.value) { _, option in
            ConfigOptionMenuView(option: option, session: agentSession)
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(spacing: 8) {
            // Toolbar with config options
            inputToolbar

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
                    .focused($isInputFocused)
                    .onSubmit {
                        if !inputText.isEmpty && !agentSession.isStreaming {
                            sendMessage()
                        }
                    }

                // Send/Stop button
                Button {
                    if agentSession.isStreaming {
                        Task {
                            await agentSession.cancelCurrentPrompt()
                        }
                    } else {
                        sendMessage()
                    }
                } label: {
                    Image(systemName: agentSession.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            agentSession.isStreaming ? .red : (canSend ? Color.accentColor : Color.secondary))
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !agentSession.isStreaming)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var canSend: Bool {
        !inputText.isEmpty && agentSession.sessionState.isReady && !agentSession.isStreaming
    }

    // MARK: - Actions

    private func startSession() async {
        guard !agentSession.isActive else { return }
        isInitializing = true

        // Register agent session with manager (this also restores cached messages)
        sessionManager.setAgentSession(agentSession, for: chatSession.id)

        do {
            if let externalId = chatSession.externalSessionId {
                try await agentSession.start(
                    workingDirectory: chatSession.repositoryPath,
                    resumeSessionId: externalId
                )
            } else {
                try await agentSession.start(workingDirectory: chatSession.repositoryPath)
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isInitializing = false
    }

    private func sendMessage() {
        guard canSend else { return }
        let message = inputText
        inputText = ""

        Task {
            do {
                try await agentSession.sendMessage(content: message)
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
    let agentName: String?

    @State private var showCopyConfirmation = false

    init(message: MessageItem, agentName: String? = nil) {
        self.message = message
        self.agentName = agentName
    }

    private var shouldShowMessage: Bool {
        guard message.role == .agent else { return true }
        return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            // Agent header
            if message.role == .agent, shouldShowMessage {
                HStack(spacing: 6) {
                    if let name = agentName,
                        let metadata = AgentRegistry.shared.getMetadata(for: name)
                    {
                        AgentIconView(iconType: metadata.iconType, size: 16)
                    }
                    Text(agentDisplayName)
                        .font(.system(size: 12, weight: .semibold))
                }
            }

            // Message content
            if message.role == .user {
                userMessageBubble
            } else if message.role == .agent && shouldShowMessage {
                agentMessageContent
            } else if message.role == .system {
                systemMessage
            }

            // Tool calls (for agent messages)
            if message.role == .agent && !message.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(message.toolCalls, id: \.toolCallId) { toolCall in
                        ToolCallView(toolCall: toolCall)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var agentDisplayName: String {
        if let name = agentName, let meta = AgentRegistry.shared.getMetadata(for: name) {
            return meta.name
        }
        return agentName ?? "Agent"
    }

    // MARK: - User Message Bubble

    private var userMessageBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(message.content)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                )
                .contextMenu {
                    Button {
                        copyMessage()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

            // Timestamp and copy button
            HStack(spacing: 8) {
                Text(DateFormatters.shortTime.string(from: message.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Button(action: copyMessage) {
                    Image(systemName: showCopyConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(showCopyConfirmation ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 400, alignment: .trailing)
    }

    // MARK: - Agent Message Content

    private var agentMessageContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Parse and render content with code blocks
            let segments = CodeBlockParser.segments(message.content)

            ForEach(segments) { segment in
                switch segment {
                case .text(let text):
                    Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 13))
                        .textSelection(.enabled)

                case .code(let block):
                    CodeBlockView(block: block)
                }
            }

            // Footer with timestamp and execution time
            HStack(spacing: 8) {
                Text(DateFormatters.shortTime.string(from: message.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                if message.isComplete, let time = message.executionTime {
                    Text(DurationFormatter.short(time))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - System Message

    private var systemMessage: some View {
        Text(message.content)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func copyMessage() {
        Clipboard.copy(message.content)
        withAnimation {
            showCopyConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let block: CodeBlock

    @State private var isHovering = false
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language
            if let language = block.language {
                HStack {
                    Text(language)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        copyCode()
                    } label: {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(showCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering || showCopied ? 1 : 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
            }

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.code)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func copyCode() {
        Clipboard.copy(block.code)
        withAnimation {
            showCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
            }
        }
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
