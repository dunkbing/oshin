//
//  ACPRequestRouter.swift
//  oshin
//
//  Routes incoming ACP requests to appropriate handlers
//

import Foundation
import os.log

actor ACPRequestRouter {
    // MARK: - Properties

    private weak var delegate: ACPRequestDelegate?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: Logger

    // MARK: - Initialization

    init(encoder: JSONEncoder, decoder: JSONDecoder) {
        self.encoder = encoder
        self.decoder = decoder
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.oshin",
            category: "ACPRequestRouter"
        )
    }

    // MARK: - Configuration

    func setDelegate(_ delegate: ACPRequestDelegate) {
        self.delegate = delegate
    }

    // MARK: - Request Handling

    func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        logger.debug("Handling request: \(request.method)")

        do {
            guard let delegate = delegate else {
                throw ACPClientError.delegateNotSet
            }

            let result: Any

            switch request.method {
            case "fs/read_text_file":
                let params = try decodeParams(ReadTextFileRequest.self, from: request.params)
                result = try await delegate.handleFileRead(
                    path: params.path,
                    sessionId: params.sessionId,
                    line: params.line,
                    limit: params.limit
                )

            case "fs/write_text_file":
                let params = try decodeParams(WriteTextFileRequest.self, from: request.params)
                result = try await delegate.handleFileWrite(
                    path: params.path,
                    content: params.content,
                    sessionId: params.sessionId
                )

            case "terminal/create":
                let params = try decodeParams(CreateTerminalRequest.self, from: request.params)
                result = try await delegate.handleTerminalCreate(request: params)

            case "terminal/output":
                let params = try decodeParams(TerminalOutputRequest.self, from: request.params)
                result = try await delegate.handleTerminalOutput(request: params)

            case "terminal/kill":
                let params = try decodeParams(KillTerminalRequest.self, from: request.params)
                result = try await delegate.handleTerminalKill(request: params)

            case "terminal/wait_for_exit":
                let params = try decodeParams(WaitForExitRequest.self, from: request.params)
                result = try await delegate.handleTerminalWaitForExit(request: params)

            case "terminal/release":
                let params = try decodeParams(ReleaseTerminalRequest.self, from: request.params)
                result = try await delegate.handleTerminalRelease(request: params)

            case "request_permission":
                let params = try decodeParams(RequestPermissionRequest.self, from: request.params)
                result = await delegate.handlePermissionRequest(request: params)

            default:
                logger.warning("Unknown method: \(request.method)")
                return createErrorResponse(
                    requestId: request.id,
                    code: -32601,
                    message: "Method not found: \(request.method)"
                )
            }

            return createSuccessResponse(requestId: request.id, result: result)

        } catch {
            logger.error("Request failed: \(error.localizedDescription)")
            return createErrorResponse(
                requestId: request.id,
                code: -32603,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Private Helpers

    private func decodeParams<T: Decodable>(_ type: T.Type, from params: AnyCodable?) throws -> T {
        guard let params = params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        return try decoder.decode(T.self, from: data)
    }

    private func createSuccessResponse(requestId: RequestId, result: Any) -> JSONRPCResponse {
        do {
            if let encodable = result as? Encodable {
                let data = try encoder.encode(AnyEncodable(encodable))
                let decoded = try decoder.decode(AnyCodable.self, from: data)
                return JSONRPCResponse(id: requestId, result: decoded, error: nil)
            }
            return JSONRPCResponse(id: requestId, result: nil, error: nil)
        } catch {
            return createErrorResponse(
                requestId: requestId,
                code: -32603,
                message: "Failed to encode response"
            )
        }
    }

    private func createErrorResponse(requestId: RequestId, code: Int, message: String)
        -> JSONRPCResponse
    {
        let error = JSONRPCError(code: code, message: message, data: nil)
        return JSONRPCResponse(id: requestId, result: nil, error: error)
    }
}

// MARK: - AnyEncodable Helper

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
