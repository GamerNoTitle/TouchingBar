import Foundation

public enum AgentHookNormalizerError: Error {
    case invalidJSON
    case invalidObject
}

public struct AgentHookNormalizer: Sendable {
    public init() {}

    public func normalize(
        data: Data,
        fallbackProvider: String = "unknown"
    ) throws -> AgentContext {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentHookNormalizerError.invalidObject
        }
        let nestedEvent = root["event"] as? [String: Any]
        let event = nestedEvent?["event"] as? [String: Any] ?? nestedEvent ?? root
        let provider = firstString(in: root, keys: ["provider", "agent", "agent_name"])
            ?? firstString(in: nestedEvent ?? [:], keys: ["provider", "agent", "agent_name"])
            ?? firstString(in: event, keys: ["provider", "agent", "agent_name"])
            ?? fallbackProvider

        let eventName = firstString(in: event, keys: [
            "hook_event_name", "event_name", "event", "type", "status"
        ]) ?? ""
        let status = status(for: eventName, payload: event)
        let task = truncate(firstString(in: event, keys: [
            "task", "prompt", "title", "summary", "command"
        ]), length: 96)
        let toolName = firstString(in: event, keys: ["tool_name", "tool", "name"])
        let workingDirectory = firstString(in: event, keys: ["cwd", "working_directory", "workingDirectory"])
        let message = truncate(firstString(in: event, keys: ["message", "notification_message", "content"]), length: 160)
        let detail = truncate(firstString(in: event, keys: [
            "detail", "description", "reason", "result"
        ]) ?? toolName, length: 160)
        let sessionID = firstString(in: event, keys: [
            "session_id", "sessionId", "thread_id", "threadId", "conversation_id"
        ])
        let startedAt = firstDate(in: event, keys: ["started_at", "startedAt", "timestamp", "created_at"])

        return AgentContext(
            provider: provider,
            task: task,
            status: status,
            detail: detail,
            sessionID: sessionID,
            event: eventName.isEmpty ? nil : eventName,
            tool: toolName,
            workingDirectory: workingDirectory,
            message: message,
            startedAt: startedAt,
            updatedAt: Date()
        )
    }

    private func status(for eventName: String, payload: [String: Any]) -> AgentStatus {
        let normalized = eventName
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        if normalized.contains("error") || normalized.contains("fail") {
            return .failed
        }
        if normalized.contains("permission") || normalized.contains("wait") || normalized.contains("notification") {
            return .waiting
        }
        if normalized.contains("stop") || normalized.contains("complete") || normalized.contains("done") || normalized.contains("finish") {
            return .completed
        }
        if normalized.contains("start")
            || normalized.contains("submit")
            || normalized.contains("pretool")
            || normalized.contains("posttool")
            || normalized.contains("running")
            || normalized.contains("progress") {
            return .running
        }
        if let value = firstString(in: payload, keys: ["status"]), let status = AgentStatus(rawValue: value.lowercased()) {
            return status
        }
        return .unknown
    }

    private func firstString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let value = object[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private func firstDate(in object: [String: Any], keys: [String]) -> Date? {
        if let value = object["started_at"] as? NSNumber ?? object["startedAt"] as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }
        for key in keys {
            guard let value = object[key] as? String else { continue }
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }
        }
        return nil
    }

    private func truncate(_ value: String?, length: Int) -> String? {
        guard let value else { return nil }
        guard value.count > length else { return value }
        return String(value.prefix(max(0, length - 1))) + "…"
    }
}
