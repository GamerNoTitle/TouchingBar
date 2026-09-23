import Foundation
import TouchingBarCore
import UserNotifications

final class AgentNotificationController {
    private var lastStatuses: [String: AgentStatus] = [:]
    private var hasSeeded = false

    func process(_ agent: AgentContext?, enabled: Bool) {
        guard let agent else { return }
        let key = agent.sessionID ?? "\(agent.provider)|\(agent.task ?? "")"
        defer { lastStatuses[key] = agent.status }

        guard hasSeeded else {
            hasSeeded = true
            lastStatuses[key] = agent.status
            return
        }
        guard enabled,
              lastStatuses[key] != agent.status,
              [.waiting, .completed, .failed].contains(agent.status),
              Bundle.main.bundleIdentifier != nil else {
            return
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
            return
        }
        content.body = agent.message ?? agent.detail ?? agent.task ?? agent.event ?? "Agent 状态已更新"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
