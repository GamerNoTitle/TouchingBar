import Foundation
import Network

public enum HookServerError: Error, LocalizedError {
    case invalidPayload
    case unsupportedPath(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "Hook 数据格式无效。"
        case .unsupportedPath(let path):
            return "不支持的 Hook 路径：\(path)"
        }
    }
}

public final class HookServer: @unchecked Sendable {
    public typealias ContextHandler = @Sendable (RuntimeContextSnapshot) -> Void

    public static let defaultPort: UInt16 = 19_427

    public var onRunningStateChange: (@Sendable (Bool) -> Void)?

    private let port: NWEndpoint.Port
    private let contextStore: RuntimeContextStore
    private let onContextChange: ContextHandler?
    private let queue = DispatchQueue(label: "app.touchingbar.hook-server")
    private var listener: NWListener?

    public init(
        port: UInt16 = HookServer.defaultPort,
        contextStore: RuntimeContextStore = .shared,
        onContextChange: ContextHandler? = nil
    ) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.contextStore = contextStore
        self.onContextChange = onContextChange
    }

    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onRunningStateChange?(true)
            case .failed, .cancelled:
                self?.onRunningStateChange?(false)
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data { accumulated.append(data) }

            if let request = self.parseRequest(accumulated) {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil || accumulated.count >= 64 * 1024 {
                self.sendResponse(status: 400, body: #"{"error":"invalid request"}"#, on: connection)
            } else {
                self.receiveRequest(on: connection, buffer: accumulated)
            }
        }
    }

    private func parseRequest(_ data: Data) -> HTTPRequest? {
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<range.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let headers = lines.dropFirst().reduce(into: [String: String]()) { result, line in
            guard let separator = line.firstIndex(of: ":") else { return }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = range.upperBound
        let available = data.count - bodyStart
        guard available >= contentLength else { return nil }
        let body = Data(data[bodyStart..<(bodyStart + contentLength)])

        return HTTPRequest(method: String(parts[0]), path: String(parts[1]), body: body)
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        if request.method == "GET", request.path == "/health" {
            sendResponse(status: 200, body: #"{"status":"ok"}"#, on: connection)
            return
        }

        guard request.method == "POST" else {
            sendResponse(status: 405, body: #"{"error":"method not allowed"}"#, on: connection)
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            switch request.path {
            case "/v1/context/developer":
                let context = try decoder.decode(DeveloperContext.self, from: request.body)
                let snapshot = try contextStore.update { $0.developer = context }
                onContextChange?(snapshot)
            case "/v1/context/agent":
                let context = try decoder.decode(AgentContext.self, from: request.body)
                let snapshot = try contextStore.update { $0.agent = context }
                onContextChange?(snapshot)
            case "/v1/hooks/agent":
                let context = try AgentHookNormalizer().normalize(data: request.body)
                let snapshot = try contextStore.update { $0.agent = context }
                onContextChange?(snapshot)
            case "/v1/messages":
                let message = try decoder.decode(MessageContext.self, from: request.body)
                let snapshot = try contextStore.update { $0.messages.insert(message, at: 0) }
                onContextChange?(snapshot)
            default:
                throw HookServerError.unsupportedPath(request.path)
            }
            sendResponse(status: 202, body: #"{"accepted":true}"#, on: connection)
        } catch {
            let payload = #"{"error":"invalid payload"}"#
            sendResponse(status: 400, body: payload, on: connection)
        }
    }

    private func sendResponse(status: Int, body: String, on connection: NWConnection) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 405: reason = "Method Not Allowed"
        default: reason = "Error"
        }
        let bodyData = Data(body.utf8)
        let headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(headers.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var body: Data
}
