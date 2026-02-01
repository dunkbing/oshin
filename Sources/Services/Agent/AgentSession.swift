//
//  AgentSession.swift
//  agentmonitor
//
//  Observable session wrapper for ACP agent communication
//

import Combine
import Foundation
import os.log

// MARK: - Message Types

struct MessageItem: Identifiable, Sendable, Codable {
    let id: String
    let role: MessageRole
    var content: String
    let timestamp: Date
    var toolCalls: [ToolCall]
    var contentBlocks: [ContentBlock]
    var isComplete: Bool
    var startTime: Date?
    var executionTime: TimeInterval?
    var requestId: String?

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolCalls: [ToolCall] = [],
        contentBlocks: [ContentBlock] = [],
        isComplete: Bool = true,
        startTime: Date? = nil,
        executionTime: TimeInterval? = nil,
        requestId: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.contentBlocks = contentBlocks
        self.isComplete = isComplete
        self.startTime = startTime
        self.executionTime = executionTime
        self.requestId = requestId
    }
}

enum MessageRole: String, Sendable, Codable {
    case user
    case agent
    case system
}

// MARK: - Session State

enum SessionState: Sendable {
    case idle
    case initializing
    case ready
    case error(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isInitializing: Bool {
        if case .initializing = self { return true }
        return false
    }
}

// MARK: - Session Errors

enum AgentSessionError: LocalizedError {
    case sessionNotActive
    case clientNotInitialized
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotActive:
            return "Session is not active"
        case .clientNotInitialized:
            return "Client not initialized"
        case .custom(let message):
            return message
        }
    }
}

// MARK: - Agent Session

@MainActor
class AgentSession: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var sessionState: SessionState = .idle
    @Published private(set) var messages: [MessageItem] = []
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var isActive: Bool = false
    @Published var needsAuthentication: Bool = false
    @Published private(set) var currentThought: String?
    @Published private(set) var currentPlan: Plan?
    @Published private(set) var authMethods: [AuthMethod] = []
    @Published private(set) var configOptions: [SessionConfigOption] = []

    // Version update state
    @Published private(set) var needsUpdate: Bool = false
    @Published private(set) var versionInfo: AgentVersionInfo?

    // MARK: - Properties

    let agentName: String
    private(set) var sessionId: SessionId?
    private var acpClient: ACPClient?
    private var notificationTask: Task<Void, Never>?
    private var versionCheckTask: Task<Void, Never>?
    private var currentIterationId: String?

    private let fileSystemDelegate = AgentFileSystemDelegate()
    private let terminalDelegate = AgentTerminalDelegate()
    private let logger: Logger

    private var agentMessageBuffer: String = ""
    private var thoughtBuffer: String = ""

    static let maxMessageCount = 500

    // MARK: - Initialization

    init(agentName: String) {
        self.agentName = agentName
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.agentmonitor",
            category: "AgentSession"
        )
    }

    deinit {
        notificationTask?.cancel()
        versionCheckTask?.cancel()
    }

    // MARK: - Session Lifecycle

    func start(workingDirectory: String, resumeSessionId: String? = nil) async throws {
        try await startSession(workingDirectory: workingDirectory, resumeSessionId: resumeSessionId)
    }

    private func startSession(workingDirectory: String, resumeSessionId: String?) async throws {
        sessionState = .initializing

        guard let agentPath = AgentRegistry.shared.getAgentPath(for: agentName) else {
            sessionState = .error("Agent not found: \(agentName)")
            throw AgentSessionError.custom("Agent not found: \(agentName)")
        }

        let metadata = AgentRegistry.shared.getMetadata(for: agentName)
        let launchArgs = metadata?.launchArgs ?? []

        let client = ACPClient()
        acpClient = client

        do {
            try await client.launch(
                agentPath: agentPath,
                arguments: launchArgs,
                workingDirectory: workingDirectory
            )

            await client.setRequestDelegate(self)

            let capabilities = ClientCapabilities(
                fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
                terminal: true,
                meta: [
                    "terminal_output": AnyCodable(true),
                    "terminal-auth": AnyCodable(true),
                ]
            )

            let initResponse = try await client.initialize(
                protocolVersion: 1,
                capabilities: capabilities
            )

            authMethods = initResponse.authMethods ?? []

            if let savedMethodId = AgentRegistry.shared.getAuthMethodId(for: agentName) {
                _ = try? await client.authenticate(methodId: savedMethodId)
            }

            // Try to resume existing session or create new one
            if let existingId = resumeSessionId {
                var resumed = false

                // Try session/resume first (matches Claude's advertised capability)
                do {
                    let resumeResponse = try await client.resumeSession(
                        sessionId: SessionId(existingId),
                        cwd: workingDirectory
                    )
                    sessionId = resumeResponse.sessionId
                    logger.info("Session resumed: \(resumeResponse.sessionId.value)")
                    resumed = true
                } catch {
                    logger.warning("session/resume failed: \(error.localizedDescription), trying session/load")
                }

                // Fall back to session/load
                if !resumed {
                    do {
                        let loadResponse = try await client.loadSession(
                            sessionId: SessionId(existingId),
                            cwd: workingDirectory
                        )
                        sessionId = loadResponse.sessionId
                        logger.info("Session loaded: \(loadResponse.sessionId.value)")
                        resumed = true
                    } catch {
                        logger.warning("session/load failed: \(error.localizedDescription), creating new session")
                    }
                }

                // Fall back to new session
                if !resumed {
                    let sessionResponse = try await client.newSession(cwd: workingDirectory)
                    sessionId = sessionResponse.sessionId

                    if let options = sessionResponse.configOptions {
                        configOptions = options
                    }
                    logger.info("New session started (resume not supported): \(sessionResponse.sessionId.value)")
                }
            } else {
                let sessionResponse = try await client.newSession(cwd: workingDirectory)
                sessionId = sessionResponse.sessionId

                if let options = sessionResponse.configOptions {
                    configOptions = options
                }
                logger.info("Session started: \(sessionResponse.sessionId.value)")
            }

            startNotificationListener()

            isActive = true
            sessionState = .ready

            // Check for agent version updates
            startVersionCheck()

        } catch {
            sessionState = .error(error.localizedDescription)
            await client.terminate()
            acpClient = nil
            throw error
        }
    }

    func close() async {
        notificationTask?.cancel()
        notificationTask = nil
        versionCheckTask?.cancel()
        versionCheckTask = nil

        if let client = acpClient {
            await client.terminate()
        }

        acpClient = nil
        sessionId = nil
        isActive = false
        sessionState = .idle

        await terminalDelegate.cleanup()
    }

    // MARK: - Messaging

    func sendMessage(content: String) async throws {
        guard sessionState.isReady else {
            if sessionState.isInitializing {
                throw AgentSessionError.custom("Session is still initializing. Please wait...")
            }
            throw AgentSessionError.sessionNotActive
        }

        guard let sessionId = sessionId, isActive else {
            throw AgentSessionError.sessionNotActive
        }

        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        currentIterationId = UUID().uuidString
        markLastMessageComplete()
        clearThoughtBuffer()

        let contentBlocks: [ContentBlock] = [.text(TextContent(text: content))]
        addUserMessage(content, contentBlocks: contentBlocks)

        isStreaming = true

        do {
            _ = try await client.sendPrompt(sessionId: sessionId, content: contentBlocks)

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                self.isStreaming = false
            }
        } catch {
            isStreaming = false
            throw error
        }
    }

    func cancelCurrentPrompt() async {
        guard let sessionId = sessionId, isActive else { return }
        guard let client = acpClient else { return }

        do {
            try await client.sendCancelNotification(sessionId: sessionId)
            isStreaming = false
            markLastMessageComplete()
            clearThoughtBuffer()
            currentThought = nil

            let cancelMessage = MessageItem(
                role: .system,
                content: "Agent stopped by user"
            )
            messages.append(cancelMessage)
        } catch {
            logger.error("Error cancelling prompt: \(error.localizedDescription)")
            isStreaming = false
            clearThoughtBuffer()
        }
    }

    func authenticate(methodId: String, credentials: [String: String]? = nil) async throws {
        guard let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        let response = try await client.authenticate(methodId: methodId, credentials: credentials)

        if response.success {
            await AgentRegistry.shared.saveAuthPreference(agentId: agentName, methodId: methodId)
            needsAuthentication = false
        } else if let error = response.error {
            throw AgentSessionError.custom(error)
        }
    }

    func setConfigOption(configId: SessionConfigId, value: SessionConfigValueId) async throws {
        guard let sessionId = sessionId, let client = acpClient else {
            throw AgentSessionError.clientNotInitialized
        }

        let response = try await client.setConfigOption(
            sessionId: sessionId,
            configId: configId,
            value: value
        )
        configOptions = response.configOptions
    }

    // MARK: - Private Methods

    private func startNotificationListener() {
        guard let client = acpClient else { return }

        notificationTask = Task {
            for await notification in await client.notificationStream() {
                await handleNotification(notification)
            }
        }
    }

    private func startVersionCheck() {
        versionCheckTask = Task { [weak self] in
            guard let self = self else { return }
            let info = await AgentVersionChecker.shared.checkVersion(for: self.agentName)
            await MainActor.run {
                self.versionInfo = info
                if let currentVersion = info.current {
                    if info.isOutdated, let latestVersion = info.latest {
                        self.needsUpdate = true
                        self.addSystemMessage(
                            "\(self.agentName) v\(currentVersion) (update available: v\(latestVersion))"
                        )
                    } else {
                        self.addSystemMessage("\(self.agentName) v\(currentVersion)")
                    }
                }
            }
        }
    }

    private func addSystemMessage(_ content: String) {
        let message = MessageItem(
            role: .system,
            content: content
        )
        messages.append(message)
        trimMessagesIfNeeded()
    }

    private func handleNotification(_ notification: JSONRPCNotification) async {
        guard notification.method == "session/update" else { return }

        guard let params = notification.params else { return }

        do {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            let data = try encoder.encode(params)
            let update = try decoder.decode(SessionUpdate.self, from: data)

            await processSessionUpdate(update)
        } catch {
            logger.error("Failed to decode session update: \(error.localizedDescription)")
        }
    }

    private func processSessionUpdate(_ update: SessionUpdate) async {
        switch update.update {
        case .agentMessageChunk(let chunk):
            appendToAgentMessage(chunk.text)

        case .agentThoughtChunk(let chunk):
            appendToThought(chunk.text)

        case .toolCall(let toolCallUpdate):
            let toolCall = ToolCall(
                toolCallId: toolCallUpdate.toolCallId,
                title: toolCallUpdate.title,
                kind: toolCallUpdate.kind,
                status: toolCallUpdate.status,
                content: toolCallUpdate.content ?? [],
                locations: toolCallUpdate.locations,
                rawInput: toolCallUpdate.rawInput,
                rawOutput: toolCallUpdate.rawOutput,
                iterationId: currentIterationId,
                parentToolCallId: toolCallUpdate.parentToolCallId
            )
            addOrUpdateToolCall(toolCall)

        case .toolCallUpdate(let progressUpdate):
            updateToolCall(progressUpdate)

        case .plan(let planUpdate):
            currentPlan = Plan(entries: planUpdate.entries)

        case .configOptions(let configUpdate):
            configOptions = configUpdate.configOptions

        case .availableCommands:
            break

        case .unknown:
            break
        }
    }

    private func appendToAgentMessage(_ text: String) {
        agentMessageBuffer += text

        if let lastIndex = messages.lastIndex(where: { $0.role == .agent && !$0.isComplete }) {
            var updatedMessages = messages
            var message = updatedMessages[lastIndex]
            message.content = agentMessageBuffer
            updatedMessages[lastIndex] = message
            messages = updatedMessages
        } else {
            flushAgentMessageBuffer()
            let newMessage = MessageItem(
                role: .agent,
                content: text,
                isComplete: false,
                startTime: Date()
            )
            messages.append(newMessage)
            agentMessageBuffer = text
        }
    }

    private func appendToThought(_ text: String) {
        thoughtBuffer += text
        currentThought = thoughtBuffer
    }

    func clearThoughtBuffer() {
        thoughtBuffer = ""
        currentThought = nil
    }

    func flushAgentMessageBuffer() {
        agentMessageBuffer = ""
    }

    private func addOrUpdateToolCall(_ toolCall: ToolCall) {
        if let lastIndex = messages.lastIndex(where: { $0.role == .agent }) {
            var updatedMessages = messages
            var message = updatedMessages[lastIndex]
            if let existingIndex = message.toolCalls.firstIndex(where: {
                $0.toolCallId == toolCall.toolCallId
            }) {
                message.toolCalls[existingIndex] = toolCall
            } else {
                message.toolCalls.append(toolCall)
            }
            updatedMessages[lastIndex] = message
            messages = updatedMessages
        } else {
            let newMessage = MessageItem(
                role: .agent,
                content: "",
                toolCalls: [toolCall],
                isComplete: false,
                startTime: Date()
            )
            messages.append(newMessage)
        }
    }

    private func updateToolCall(_ update: ToolCallProgressUpdate) {
        guard let lastIndex = messages.lastIndex(where: { $0.role == .agent }) else { return }

        var updatedMessages = messages
        var message = updatedMessages[lastIndex]

        if let toolIndex = message.toolCalls.firstIndex(where: {
            $0.toolCallId == update.toolCallId
        }) {
            var toolCall = message.toolCalls[toolIndex]

            if let title = update.title {
                toolCall.title = title
            }
            if let status = update.status {
                toolCall.status = status
            }
            if let content = update.content {
                toolCall.content = content
            }
            if let locations = update.locations {
                toolCall.locations = locations
            }
            if let rawInput = update.rawInput {
                toolCall.rawInput = rawInput
            }
            if let rawOutput = update.rawOutput {
                toolCall.rawOutput = rawOutput
            }

            message.toolCalls[toolIndex] = toolCall
            updatedMessages[lastIndex] = message
            messages = updatedMessages
        }
    }

    func addUserMessage(_ content: String, contentBlocks: [ContentBlock] = []) {
        messages.append(
            MessageItem(
                role: .user,
                content: content,
                contentBlocks: contentBlocks
            ))
        trimMessagesIfNeeded()
    }

    /// Restore messages from storage (used when restoring a session)
    func restoreMessages(_ restoredMessages: [MessageItem]) {
        messages = restoredMessages
    }

    func markLastMessageComplete() {
        flushAgentMessageBuffer()
        if let lastIndex = messages.lastIndex(where: { $0.role == .agent && !$0.isComplete }) {
            var completedMessage = messages[lastIndex]
            let executionTime = completedMessage.startTime.map { Date().timeIntervalSince($0) }
            completedMessage = MessageItem(
                id: completedMessage.id,
                role: completedMessage.role,
                content: completedMessage.content,
                timestamp: completedMessage.timestamp,
                toolCalls: completedMessage.toolCalls,
                contentBlocks: completedMessage.contentBlocks,
                isComplete: true,
                startTime: completedMessage.startTime,
                executionTime: executionTime,
                requestId: completedMessage.requestId
            )
            var updatedMessages = messages
            updatedMessages[lastIndex] = completedMessage
            messages = updatedMessages
        }
    }

    private func trimMessagesIfNeeded() {
        let excess = messages.count - Self.maxMessageCount
        guard excess > 0 else { return }
        messages.removeFirst(excess)
    }
}

// MARK: - ACPRequestDelegate

extension AgentSession: ACPRequestDelegate {
    nonisolated func handleFileRead(path: String, sessionId: String, line: Int?, limit: Int?)
        async throws -> ReadTextFileResponse
    {
        return try await fileSystemDelegate.handleFileReadRequest(
            path,
            sessionId: sessionId,
            line: line,
            limit: limit
        )
    }

    nonisolated func handleFileWrite(path: String, content: String, sessionId: String) async throws
        -> WriteTextFileResponse
    {
        return try await fileSystemDelegate.handleFileWriteRequest(
            path,
            content: content,
            sessionId: sessionId
        )
    }

    nonisolated func handleTerminalCreate(request: CreateTerminalRequest) async throws
        -> CreateTerminalResponse
    {
        return try await terminalDelegate.handleTerminalCreate(
            command: request.command,
            sessionId: request.sessionId,
            args: request.args,
            cwd: request.cwd,
            env: request.env,
            outputByteLimit: request.outputByteLimit
        )
    }

    nonisolated func handleTerminalOutput(request: TerminalOutputRequest) async throws
        -> TerminalOutputResponse
    {
        return try await terminalDelegate.handleTerminalOutput(
            terminalId: request.terminalId,
            sessionId: request.sessionId
        )
    }

    nonisolated func handleTerminalKill(request: KillTerminalRequest) async throws
        -> KillTerminalResponse
    {
        return try await terminalDelegate.handleTerminalKill(
            terminalId: request.terminalId,
            sessionId: request.sessionId
        )
    }

    nonisolated func handleTerminalWaitForExit(request: WaitForExitRequest) async throws
        -> WaitForExitResponse
    {
        return try await terminalDelegate.handleTerminalWaitForExit(
            terminalId: request.terminalId,
            sessionId: request.sessionId
        )
    }

    nonisolated func handleTerminalRelease(request: ReleaseTerminalRequest) async throws
        -> ReleaseTerminalResponse
    {
        return try await terminalDelegate.handleTerminalRelease(
            terminalId: request.terminalId,
            sessionId: request.sessionId
        )
    }

    nonisolated func handlePermissionRequest(request: RequestPermissionRequest) async
        -> RequestPermissionResponse
    {
        // For now, auto-approve all permissions
        // TODO: Add UI for permission approval
        if let firstOption = request.options?.first {
            return RequestPermissionResponse(outcome: PermissionOutcome(optionId: firstOption.optionId))
        }
        return RequestPermissionResponse(outcome: PermissionOutcome(optionId: "allow_once"))
    }
}
