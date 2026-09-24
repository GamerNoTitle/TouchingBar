import Foundation
import TouchingBarSystemMetrics

struct SystemMetricsSnapshot: Equatable {
    var cpuUsage: Double?
    var gpuUsage: Double?
    var memoryUsage: Double?
    var diskUsage: Double?
    var cpuTemperature: Double?
    var fanRPM: Double?
    var networkUpload: Double?
    var networkDownload: Double?
    var histories: [String: [Double]] = [:]

    static let empty = SystemMetricsSnapshot()

    func history(for key: String) -> [Double]? {
        histories[key]
    }

    func chartRange(for key: String) -> ClosedRange<Double>? {
        switch key {
        case "cpu", "gpu", "memory", "disk":
            return 0...100
        default:
            return nil
        }
    }

    func value(for key: String) -> String? {
        switch key {
        case "cpu":
            return cpuUsage.map { String(format: "%.0f%%", $0) }
        case "gpu":
            return gpuUsage.map { String(format: "%.0f%%", $0) }
        case "memory":
            return memoryUsage.map { String(format: "%.0f%%", $0) }
        case "disk":
            return diskUsage.map { String(format: "%.0f%%", $0) }
        case "cpuTemperature":
            return cpuTemperature.map { String(format: "%.1f°C", $0) }
        case "fanRPM":
            return fanRPM.map { String(format: "%.0f RPM", $0) }
        case "networkDownload":
            return networkDownload.map { Self.speed($0, prefix: "↓") }
        case "networkUpload":
            return networkUpload.map { Self.speed($0, prefix: "↑") }
        default:
            return nil
        }
    }

    private static func speed(_ bytesPerSecond: Double, prefix: String) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%@ %.1f MB/s", prefix, bytesPerSecond / 1_048_576)
        }
        if bytesPerSecond >= 1_024 {
            return String(format: "%@ %.1f KB/s", prefix, bytesPerSecond / 1_024)
        }
        return String(format: "%@ %.0f B/s", prefix, bytesPerSecond)
    }
}

final class SystemMetricsService {
    private let queue = DispatchQueue(label: "app.touchingbar.system-metrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var histories: [String: [Double]] = [:]
    private let historyLimit = 30

    func start(handler: @escaping (SystemMetricsSnapshot) -> Void) {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler {
            let raw = TBSystemMetricsSample()
            var snapshot = SystemMetricsSnapshot(
                cpuUsage: raw.hasCPUUsage.boolValue ? raw.cpuUsagePercent : nil,
                gpuUsage: raw.hasGPUUsage.boolValue ? raw.gpuUsagePercent : nil,
                memoryUsage: raw.hasMemoryUsage.boolValue ? raw.memoryUsagePercent : nil,
                diskUsage: raw.hasDiskUsage.boolValue ? raw.diskUsagePercent : nil,
                cpuTemperature: raw.hasCPUTemperature.boolValue ? raw.cpuTemperatureCelsius : nil,
                fanRPM: raw.hasFanRPM.boolValue ? raw.fanRPM : nil,
                networkUpload: raw.hasNetworkUsage.boolValue ? raw.networkUploadBytesPerSecond : nil,
                networkDownload: raw.hasNetworkUsage.boolValue ? raw.networkDownloadBytesPerSecond : nil
            )
            self.appendHistory(snapshot.cpuUsage, for: "cpu")
            self.appendHistory(snapshot.gpuUsage, for: "gpu")
            self.appendHistory(snapshot.memoryUsage, for: "memory")
            self.appendHistory(snapshot.diskUsage, for: "disk")
            self.appendHistory(snapshot.cpuTemperature, for: "cpuTemperature")
            self.appendHistory(snapshot.fanRPM, for: "fanRPM")
            self.appendHistory(snapshot.networkDownload, for: "networkDownload")
            self.appendHistory(snapshot.networkUpload, for: "networkUpload")
            snapshot.histories = self.histories
            DispatchQueue.main.async { handler(snapshot) }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func appendHistory(_ value: Double?, for key: String) {
        guard let value else { return }
        var values = histories[key] ?? []
        values.append(value)
        if values.count > historyLimit {
            values.removeFirst(values.count - historyLimit)
        }
        histories[key] = values
    }
}
