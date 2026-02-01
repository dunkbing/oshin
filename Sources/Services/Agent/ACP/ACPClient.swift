//
//  ACPClient.swift
//  agentmonitor
//
//  Agent Client Protocol client - manages subprocess communication
//

import Darwin
import Foundation
import os.log

actor ACPClient {
    // MARK: - Properties

    private let processManager: ACPProcessManager
    private let requestRouter: ACPRequestRouter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: Logger

    private var nextRequestId: Int = 1
    private var pendingRequests: [RequestId: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation?

    // Timeout for requests
    private let requestTimeout: Duration = .seconds(300)

    // MARK: - Initialization

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        decoder = JSONDecoder()
        logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.agentmonitor",
            category: "ACPClient"
        )
        processManager = ACPProcessManager(encoder: encoder, decoder: decoder)
        requestRouter = ACPRequestRouter(encoder: encoder, decoder: decoder)
    }

    // MARK: - Process Lifecycle

    func launch(agentPath: String, arguments: [String] = [], workingDirectory: String? = nil)
        async throws
    {
        try await processManager.launch(
            agentPath: agentPath,
            arguments: arguments,
            workingDirectory: workingDirectory
        )

        await processManager.setDataReceivedCallback { [weak self] data in
            await self?.handleIncomingData(data)
        }

        await processManager.setTerminationCallback { [weak self] exitCode in
            await self?.handleTermination(exitCode: exitCode)
        }
    }

    func terminate() async {
        notificationContinuation?.finish()
        notificationContinuation = nil

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: ACPClientError.processNotRunning)
        }
        pendingRequests.removeAll()

        await processManager.terminate()
    }

    func isRunning() async -> Bool {
        return await processManager.isRunning()
    }

    // MARK: - Notification Stream

    func notificationStream() -> AsyncStream<JSONRPCNotification> {
        return AsyncStream { continuation in
            self.notificationContinuation = continuation
        }
    }

    // MARK: - ACP Methods

    func initialize(protocolVersion: Int, capabilities: ClientCapabilities) async throws
        -> InitializeResponse
    {
        print("Sending initialize request...")
        let params = InitializeRequest(
            protocolVersion: protocolVersion,
            clientCapabilities: capabilities,
            clientInfo: ClientInfo(name: "AgentMonitor", version: "1.0.0")
        )
        let response: InitializeResponse = try await sendRequest(method: "initialize", params: params)
        print("Initialize response received: \(response.agentInfo?.name ?? "unknown")")
        return response
    }

    func newSession(cwd: String, mcpServers: [MCPServerConfig] = []) async throws
        -> NewSessionResponse
    {
        let params = NewSessionRequest(cwd: cwd, mcpServers: mcpServers)
        return try await sendRequest(method: "session/new", params: params)
    }

    func loadSession(
        sessionId: SessionId,
        cwd: String? = nil,
        mcpServers: [MCPServerConfig]? = nil
    ) async throws -> LoadSessionResponse {
        let params = LoadSessionRequest(
            sessionId: sessionId,
            cwd: cwd,
            mcpServers: mcpServers
        )
        return try await sendRequest(method: "session/load", params: params)
    }

    func sendPrompt(sessionId: SessionId, content: [ContentBlock]) async throws
        -> SessionPromptResponse
    {
        let params = SessionPromptRequest(sessionId: sessionId, prompt: content)
        return try await sendRequest(method: "session/prompt", params: params, timeout: .seconds(600))
    }

    func cancelSession(sessionId: SessionId) async throws {
        let params = CancelSessionRequest(sessionId: sessionId)
        let _: AnyCodable? = try await sendRequest(method: "session/cancel", params: params)
    }

    func authenticate(methodId: String, credentials: [String: String]? = nil) async throws
        -> AuthenticateResponse
    {
        let params = AuthenticateRequest(methodId: methodId, credentials: credentials)
        return try await sendRequest(method: "authenticate", params: params)
    }

    func setMode(sessionId: SessionId, modeId: String) async throws -> SetModeResponse {
        let params = SetModeRequest(sessionId: sessionId, modeId: modeId)
        return try await sendRequest(method: "session/set_mode", params: params)
    }

    func setModel(sessionId: SessionId, modelId: String) async throws -> SetModelResponse {
        let params = SetModelRequest(sessionId: sessionId, modelId: modelId)
        return try await sendRequest(method: "session/set_model", params: params)
    }

    func setConfigOption(sessionId: SessionId, configId: SessionConfigId, value: SessionConfigValueId)
        async throws -> SetSessionConfigOptionResponse
    {
        let params = SetSessionConfigOptionRequest(
            sessionId: sessionId,
            configId: configId,
            value: value
        )
        return try await sendRequest(method: "session/set_config_option", params: params)
    }

    func sendCancelNotification(sessionId: SessionId) async throws {
        let params = CancelSessionRequest(sessionId: sessionId)
        try await sendNotification(method: "notifications/cancel", params: params)
    }

    // MARK: - Request Handling

    func setRequestDelegate(_ delegate: ACPRequestDelegate) async {
        await requestRouter.setDelegate(delegate)
    }

    // MARK: - Private Methods

    private func sendRequest<P: Encodable, R: Decodable>(
        method: String,
        params: P,
        timeout: Duration? = nil
    ) async throws -> R {
        let requestId = RequestId.number(nextRequestId)
        nextRequestId += 1

        print("Sending request: \(method) (id: \(self.nextRequestId - 1))")

        let request = JSONRPCRequest(id: requestId, method: method, params: AnyCodable(params))

        // Debug: log the full request JSON
        if let requestData = try? encoder.encode(request),
            let requestJson = String(data: requestData, encoding: .utf8)
        {
            print(">>> ACP Request [\(method)]: \(requestJson)")
        }

        let response: JSONRPCResponse = try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation

            Task {
                do {
                    try await processManager.writeMessage(request)
                    logger.debug("Request \(method) written to process")
                } catch {
                    logger.error("Failed to write request \(method): \(error.localizedDescription)")
                    if let cont = pendingRequests.removeValue(forKey: requestId) {
                        cont.resume(throwing: error)
                    }
                }
            }

            Task {
                try? await Task.sleep(for: timeout ?? requestTimeout)
                if let cont = pendingRequests.removeValue(forKey: requestId) {
                    logger.warning("Request \(method) timed out")
                    cont.resume(throwing: ACPClientError.requestTimeout)
                }
            }
        }

        print("Received response for \(method)")

        if let error = response.error {
            print("<<< ACP Error [\(method)]: code=\(error.code) message=\(error.message)")
            if let data = error.data {
                if let dataJson = try? encoder.encode(data),
                    let dataStr = String(data: dataJson, encoding: .utf8)
                {
                    print("<<< ACP Error data: \(dataStr)")
                }
            }
            print("Request \(method) returned error: \(error.message)")
            throw ACPClientError.agentError(error)
        }

        guard let result = response.result else {
            print("<<< ACP Response [\(method)]: result is nil, using empty object")
            return try decoder.decode(R.self, from: "{}".data(using: .utf8)!)
        }

        let data = try encoder.encode(result)
        if let resultJson = String(data: data, encoding: .utf8) {
            print("<<< ACP Response [\(method)]: \(resultJson.prefix(1000))")
        }

        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            print("<<< ACP Decode Error [\(method)]: \(error)")
            throw error
        }
    }

    private func sendNotification<P: Encodable>(method: String, params: P) async throws {
        let notification = JSONRPCNotification(
            method: method,
            params: AnyCodable(params)
        )
        try await processManager.writeMessage(notification)
    }

    private func handleIncomingData(_ data: Data) async {
        if let rawJson = String(data: data, encoding: .utf8) {
            print("<<< Raw incoming data: \(rawJson.prefix(500))")
        }

        do {
            let message = try decoder.decode(ACPMessage.self, from: data)

            switch message {
            case .response(let response):
                print("<<< Decoded as response, id=\(response.id)")
                if let continuation = pendingRequests.removeValue(forKey: response.id) {
                    continuation.resume(returning: response)
                } else {
                    print("<<< WARNING: No pending request for id=\(response.id)")
                }

            case .notification(let notification):
                print("<<< Decoded as notification: \(notification.method)")
                notificationContinuation?.yield(notification)

            case .request(let request):
                print("<<< Decoded as request: \(request.method)")
                let response = await requestRouter.handleRequest(request)
                try await processManager.writeMessage(response)
            }
        } catch {
            print("<<< Failed to decode message: \(error)")
            logger.error("Failed to decode message: \(error.localizedDescription)")
        }
    }

    private func handleTermination(exitCode: Int32) async {
        logger.info("Agent process terminated with code: \(exitCode)")

        notificationContinuation?.finish()
        notificationContinuation = nil

        let error =
            exitCode == 0
            ? ACPClientError.processNotRunning : ACPClientError.processFailed(exitCode)

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: error)
        }
        pendingRequests.removeAll()
    }
}

// MARK: - Error Types

enum ACPClientError: Error, LocalizedError {
    case processNotRunning
    case processFailed(Int32)
    case invalidResponse
    case requestTimeout
    case encodingError
    case decodingError(Error)
    case agentError(JSONRPCError)
    case delegateNotSet
    case fileNotFound(String)
    case fileOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .processNotRunning:
            return "Agent process is not running"
        case .processFailed(let code):
            return "Agent process failed with exit code \(code)"
        case .invalidResponse:
            return "Invalid response from agent"
        case .requestTimeout:
            return "Request timed out"
        case .encodingError:
            return "Failed to encode request"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .agentError(let jsonError):
            // Extract the actual error message from the JSON-RPC error

            // Case 1: data is a plain string (Codex)
            if let dataString = jsonError.data?.value as? String {
                return dataString
            }

            // Case 2: data is an object with details
            if let data = jsonError.data?.value as? [String: Any],
                let details = data["details"] as? String
            {
                // Try to parse nested error details (Gemini)
                if let detailsData = details.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: detailsData) as? [String: Any],
                    let error = json["error"] as? [String: Any],
                    let message = error["message"] as? String
                {
                    return message
                }
                return details
            }

            // Case 3: Fallback to generic message
            return jsonError.message
        case .delegateNotSet:
            return "Internal error: Delegate not set"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileOperationFailed(let message):
            return "File operation failed: \(message)"
        }
    }
}

// MARK: - Request Delegate Protocol

protocol ACPRequestDelegate: AnyObject, Sendable {
    func handleFileRead(path: String, sessionId: String, line: Int?, limit: Int?) async throws
        -> ReadTextFileResponse
    func handleFileWrite(path: String, content: String, sessionId: String) async throws
        -> WriteTextFileResponse
    func handleTerminalCreate(request: CreateTerminalRequest) async throws -> CreateTerminalResponse
    func handleTerminalOutput(request: TerminalOutputRequest) async throws -> TerminalOutputResponse
    func handleTerminalKill(request: KillTerminalRequest) async throws -> KillTerminalResponse
    func handleTerminalWaitForExit(request: WaitForExitRequest) async throws -> WaitForExitResponse
    func handleTerminalRelease(request: ReleaseTerminalRequest) async throws
        -> ReleaseTerminalResponse
    func handlePermissionRequest(request: RequestPermissionRequest) async
        -> RequestPermissionResponse
}
