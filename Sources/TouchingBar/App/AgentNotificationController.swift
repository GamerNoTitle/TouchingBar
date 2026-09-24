import Foundation
import TouchingBarCore
import UserNotifications

final class AgentNotificationController {
    private var lastStatuses: [String: AgentStatus] = [:]
    private var hasSeeded = false

    func process(_ agents: [AgentContext], enabled: Bool) {
        var currentStatuses: [String: AgentStatus] = [:]
        for agent in agents {
            currentStatuses[notificationKey(for: agent)] = agent.status
        }
        guard hasSeeded else {
            hasSeeded = true
            lastStatuses = currentStatuses
            return
        }

        lastStatuses = lastStatuses.filter { currentStatuses[$0.key] != nil }
        for agent in agents {
            let key = notificationKey(for: agent)
            defer { lastStatuses[key] = agent.status }
            guard enabled,
                  lastStatuses[key] != agent.status,
                  [.waiting, .completed, .failed].contains(agent.status),
                  Bundle.main.bundleIdentifier != nil else {
                continue
            }

            let content = UNMutableNotificationContent()
            switch agent.status {
            case .waiting:
                content.title = "\(agent.provider) 等待处理"
            case .completed:
                content.title = "\(agent.provider) 任务完成"
            case .failed:
                content.title = "\(agent.provider) 执行失败"
            default:
                continue
            }
            content.body = agent.message ?? agent.detail ?? agent.task ?? agent.event ?? "Agent 状态已更新"
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
        }
    }

    private func notificationKey(for agent: AgentContext) -> String {
        agent.sessionID ?? "\(agent.provider)|\(agent.workingDirectory ?? "")|\(agent.task ?? "")"
    }
}
