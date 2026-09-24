import Foundation

public enum WebDAVError: Error, LocalizedError {
    case invalidServerURL
    case invalidResponse
    case authenticationFailed
    case httpStatus(Int, String?)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "WebDAV 服务器地址无效。"
        case .invalidResponse:
            return "WebDAV 服务器返回了无效响应。"
        case .authenticationFailed:
            return "WebDAV 认证失败，请检查用户名和密码。"
        case .httpStatus(let code, let message):
            return "WebDAV 请求失败（HTTP \(code)）\(message.map { "：\($0)" } ?? "")"
        }
    }
}

public struct WebDAVClient: Sendable {
    public init() {}

    public func upload(
        _ data: Data,
        settings: WebDAVSettings,
        password: String
    ) async throws {
        let url = try remoteURL(settings: settings)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthorization(to: &request, username: settings.username, password: password)
        _ = try await perform(request)
    }

    public func download(
        settings: WebDAVSettings,
        password: String
    ) async throws -> Data {
        let url = try remoteURL(settings: settings)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthorization(to: &request, username: settings.username, password: password)
        return try await perform(request)
    }

    private func remoteURL(settings: WebDAVSettings) throws -> URL {
        guard var base = URL(string: settings.serverURL), base.scheme != nil, base.host != nil else {
            throw WebDAVError.invalidServerURL
        }
        for component in settings.remotePath.split(separator: "/") {
            base.appendPathComponent(String(component), isDirectory: false)
        }
        return base
    }

    private func addAuthorization(to request: inout URLRequest, username: String, password: String) {
        guard !username.isEmpty else { return }
        let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw WebDAVError.authenticationFailed
            }
            let message = String(data: data, encoding: .utf8)
            throw WebDAVError.httpStatus(response.statusCode, message)
        }
        return data
    }
}
