import Foundation

/// Network identity is separate from throughput metrics and is never persisted as configuration.
public struct NetworkStatusSnapshot: Equatable, Sendable {
    public enum WiFiState: String, Sendable {
        case unknown, unavailable, poweredOff, disconnected, ssidUnavailable, connected
    }
    public enum VPNState: String, Sendable {
        case unknown, noTunnelDetected, tunnelDetected
    }
    public enum LatencyResult: Equatable, Sendable {
        case milliseconds(Double)
        case unavailable
    }

    public static let contextKeys: Set<String> = ["wifiSSID", "localIP", "vpnStatus", "networkLatency"]
    public var wifiState: WiFiState
    public var wifiSSID: String?
    public var localIP: String?
    public var vpnState: VPNState
    public var latencyByHost: [String: LatencyResult]

    public init(wifiState: WiFiState = .unknown, wifiSSID: String? = nil,
                localIP: String? = nil, vpnState: VPNState = .unknown,
                latencyByHost: [String: LatencyResult] = [:]) {
        self.wifiState = wifiState
        self.wifiSSID = wifiSSID
        self.localIP = localIP
        self.vpnState = vpnState
        self.latencyByHost = latencyByHost
    }

    public static let empty = NetworkStatusSnapshot()

    /// Accept only a host, never a URL, command, or ping option. IPv4, IPv6 and ASCII DNS names work.
    public static func normalizedProbeHost(_ host: String?) -> String? {
        guard let host = host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty, host.utf8.count <= 253,
              host.first != "-", host.first != ".",
              host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:").contains($0) }),
              host.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return host.lowercased()
    }

    public func value(for key: String, host: String? = nil) -> String? {
        switch key {
        case "wifiSSID":
            switch wifiState {
            case .connected: return wifiSSID ?? "SSID 不可用"
            case .ssidUnavailable: return "SSID 不可用（权限受限或未连接）"
            case .poweredOff: return "Wi-Fi 已关闭"
            case .disconnected: return "Wi-Fi 未连接"
            case .unavailable: return "无 Wi-Fi 接口"
            case .unknown: return "Wi-Fi 状态未知"
            }
        case "localIP": return localIP ?? "无本地 IP"
        case "vpnStatus":
            switch vpnState {
            case .unknown: return "VPN 状态未知"
            case .noTunnelDetected: return "未检测到 VPN 隧道（推测）"
            case .tunnelDetected: return "检测到 VPN 类隧道（推测）"
            }
        case "networkLatency":
            guard let raw = host, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "未启用探测" }
            guard let host = Self.normalizedProbeHost(raw) else { return "探测地址无效" }
            switch latencyByHost[host] {
            case .milliseconds(let value): return String(format: "%.0f ms", value)
            case .unavailable: return "超时或不可达"
            case nil: return "等待探测"
            }
        default: return nil
        }
    }
}
