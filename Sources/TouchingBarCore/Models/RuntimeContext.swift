import Foundation

public struct DeveloperContext: Codable, Equatable, Sendable {
    public var workingDirectory: String?
    public var terminalName: String?
    public var branch: String?
    public var ahead: Int
    public var behind: Int
    public var added: Int
    public var modified: Int
    public var deleted: Int
    public var pythonEnvironment: String?
    public var pythonVersion: String?
    public var nodeVersion: String?
    public var packageManager: String?
    public var toolchains: [String: String]?
    public var updatedAt: Date?

    public init(
        workingDirectory: String? = nil,
        terminalName: String? = nil,
        branch: String? = nil,
        ahead: Int = 0,
        behind: Int = 0,
        added: Int = 0,
        modified: Int = 0,
        deleted: Int = 0,
        pythonEnvironment: String? = nil,
        pythonVersion: String? = nil,
        nodeVersion: String? = nil,
        packageManager: String? = nil,
        toolchains: [String: String]? = nil,
        updatedAt: Date? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.terminalName = terminalName
        self.branch = branch
        self.ahead = ahead
        self.behind = behind
        self.added = added
        self.modified = modified
        self.deleted = deleted
        self.pythonEnvironment = pythonEnvironment
        self.pythonVersion = pythonVersion
        self.nodeVersion = nodeVersion
        self.packageManager = packageManager
        self.toolchains = toolchains
        self.updatedAt = updatedAt
    }

    public var compactPath: String {
        guard let workingDirectory, !workingDirectory.isEmpty else { return "—" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let display = workingDirectory.hasPrefix(home)
            ? "~" + workingDirectory.dropFirst(home.count)
            : workingDirectory
        let components = display.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count > 3 else { return display }
        return "…/" + components.suffix(2).joined(separator: "/")
    }

    public var diffSummary: String {
        "+\(added) -\(deleted)" + (modified > 0 ? " ~\(modified)" : "")
    }
}

public enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case idle
    case running
    case waiting
    case completed
    case failed
    case unknown
}

public struct AgentContext: Codable, Equatable, Sendable {
    public var provider: String
    public var task: String?
    public var status: AgentStatus
    public var detail: String?
    public var sessionID: String?
    public var event: String?
    public var tool: String?
    public var workingDirectory: String?
    public var message: String?
    public var startedAt: Date?
    public var updatedAt: Date

    public init(
        provider: String,
        task: String? = nil,
        status: AgentStatus = .unknown,
        detail: String? = nil,
        sessionID: String? = nil,
        event: String? = nil,
        tool: String? = nil,
        workingDirectory: String? = nil,
        message: String? = nil,
        startedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.provider = provider
        self.task = task
        self.status = status
        self.detail = detail
        self.sessionID = sessionID
        self.event = event
        self.tool = tool
        self.workingDirectory = workingDirectory
        self.message = message
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var durationText: String {
        guard let startedAt else { return "—" }
        let interval = max(0, updatedAt.timeIntervalSince(startedAt))
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }
}

public struct MessageContext: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var application: String
    public var bundleIdentifier: String?
    public var sender: String?
    public var body: String
    public var conversation: String?
    public var unreadCount: Int
    public var receivedAt: Date

    public init(
        id: UUID = UUID(),
        application: String,
        bundleIdentifier: String? = nil,
        sender: String? = nil,
        body: String,
        conversation: String? = nil,
        unreadCount: Int = 1,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.application = application
        self.bundleIdentifier = bundleIdentifier
        self.sender = sender
        self.body = body
        self.conversation = conversation
        self.unreadCount = unreadCount
        self.receivedAt = receivedAt
    }
}

public struct RuntimeContextSnapshot: Codable, Equatable, Sendable {
    public var developer: DeveloperContext?
    public var agent: AgentContext?
    public var agents: [AgentContext]?
    public var messages: [MessageContext]

    public init(
        developer: DeveloperContext? = nil,
        agent: AgentContext? = nil,
        agents: [AgentContext]? = nil,
        messages: [MessageContext] = []
    ) {
        self.developer = developer
        self.agent = agent
        self.agents = agents
        self.messages = messages
    }

    public mutating func upsertAgent(_ context: AgentContext) {
        var list = agents ?? agent.map { [$0] } ?? []
        if let sessionID = context.sessionID,
           let index = list.firstIndex(where: { $0.sessionID == sessionID }) {
            list[index] = context
        } else {
            list.removeAll { $0.provider == context.provider && $0.task == context.task }
            list.insert(context, at: 0)
        }
        list.sort { $0.updatedAt > $1.updatedAt }
        agents = Array(list.prefix(10))
        agent = context
    }

    public func value(for contextKey: String) -> String? {
        switch contextKey {
        case "path":
            return developer?.compactPath
        case "branch":
            return developer?.branch ?? "无 Git"
        case "changes":
            return developer?.diffSummary
        case "python":
            guard let developer else { return nil }
            if let name = developer.pythonEnvironment, let version = developer.pythonVersion {
                return "\(name) \(version)"
            }
            return developer.pythonVersion ?? developer.pythonEnvironment
        case "node":
            guard let developer else { return nil }
            if let version = developer.nodeVersion, let manager = developer.packageManager {
                return "\(manager) \(version)"
            }
            return developer.nodeVersion ?? developer.packageManager
        case "java", "go", "rust", "ruby", "php", "swift",
             "docker", "kubernetes", "terraform", "cmake", "xcode":
            return developer?.toolchains?[contextKey]
        case "provider":
            return agent?.provider
        case "task":
            return agent?.task
        case "status":
            return agent?.status.rawValue
        case "detail":
            return agent?.detail
        case "duration":
            return agent?.durationText
        case "event":
            return agent?.event
        case "tool":
            return agent?.tool
        case "cwd":
            guard let path = agent?.workingDirectory else { return nil }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        case "message":
            return agent?.message
        case "sessions":
            let sessions = agents ?? agent.map { [$0] } ?? []
            guard !sessions.isEmpty else { return nil }
            return sessions.prefix(4).map { "\($0.provider): \($0.status.rawValue)" }.joined(separator: " · ")
        default:
            return nil
        }
    }
}
