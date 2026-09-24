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
    var batteryLevel: Double?
    var batteryPower: Double?
    var batteryTimeMinutes: Double?
    var batteryIsCharging: Bool = false
    var batteryIsPluggedIn: Bool = false
    var batteryIsFullyCharged: Bool = false
    var histories: [String: [Double]] = [:]

    static let empty = SystemMetricsSnapshot()

    var hasAnyValue: Bool {
        cpuUsage != nil
            || gpuUsage != nil
            || memoryUsage != nil
            || diskUsage != nil
            || cpuTemperature != nil
            || fanRPM != nil
            || networkUpload != nil
            || networkDownload != nil
            || batteryLevel != nil
            || batteryPower != nil
            || batteryTimeMinutes != nil
    }

    func history(for key: String) -> [Double]? {
        histories[key]
    }

    func chartRange(for key: String, history: [Double]) -> ClosedRange<Double>? {
        if ["cpu", "gpu", "memory", "disk", "battery"].contains(key) {
            return 0...100
        }
        guard let minimum = history.min(), let maximum = history.max() else {
            return nil
        }

        let span = maximum - minimum
        let minimumSpan = max(abs(maximum) * 0.001, 0.0001)
        let expandedMinimum: Double
        let expandedMaximum: Double
        if span <= minimumSpan {
            let expansion = max(abs(maximum) * 0.05, 1)
            expandedMinimum = max(0, maximum - expansion)
            expandedMaximum = maximum + expansion
        } else {
            let padding = span * 0.05
            expandedMinimum = minimum == 0 ? 0 : Swift.max(0, minimum - padding)
            expandedMaximum = maximum + padding
        }
        return expandedMinimum...max(expandedMinimum + 0.0001, expandedMaximum)
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
        case "battery":
            return batteryLevel.map { level in
                batteryIsCharging ? String(format: "⚡ %.0f%%", level) : String(format: "%.0f%%", level)
            }
        case "batteryPower":
            return batteryPower.map { watts in
                batteryIsCharging ? String(format: "⚡ %.1f W", watts) : String(format: "%.1f W", watts)
            }
        case "batteryTime":
            guard let minutes = batteryTimeMinutes else {
                return batteryIsPluggedIn && batteryIsFullyCharged ? "已充满" : nil
            }
            let formatted = Self.duration(minutes: minutes)
            if batteryIsPluggedIn {
                return batteryIsFullyCharged ? "已充满" : "充满 \(formatted)"
            }
            return "剩余 \(formatted)"
        default:
            return nil
        }
    }

    private static func duration(minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        let hours = total / 60
        let remainingMinutes = total % 60
        if hours > 0 {
            return "\(hours)h\(remainingMinutes)m"
        }
        return "\(remainingMinutes)m"
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
    private var historyLimit = 30

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
                networkDownload: raw.hasNetworkUsage.boolValue ? raw.networkDownloadBytesPerSecond : nil,
                batteryLevel: raw.hasBatteryLevel.boolValue ? raw.batteryLevelPercent : nil,
                batteryPower: raw.hasBatteryPower.boolValue ? raw.batteryPowerWatts : nil,
                batteryTimeMinutes: raw.hasBatteryTime.boolValue ? raw.batteryTimeMinutes : nil,
                batteryIsCharging: raw.batteryIsCharging.boolValue,
                batteryIsPluggedIn: raw.batteryIsPluggedIn.boolValue,
                batteryIsFullyCharged: raw.batteryIsFullyCharged.boolValue
            )
            self.appendHistory(snapshot.cpuUsage, for: "cpu")
            self.appendHistory(snapshot.gpuUsage, for: "gpu")
            self.appendHistory(snapshot.memoryUsage, for: "memory")
            self.appendHistory(snapshot.diskUsage, for: "disk")
            self.appendHistory(snapshot.cpuTemperature, for: "cpuTemperature")
            self.appendHistory(snapshot.fanRPM, for: "fanRPM")
            self.appendHistory(snapshot.networkDownload, for: "networkDownload")
            self.appendHistory(snapshot.networkUpload, for: "networkUpload")
            self.appendHistory(snapshot.batteryLevel, for: "battery")
            self.appendHistory(snapshot.batteryPower, for: "batteryPower")
            self.appendHistory(snapshot.batteryTimeMinutes, for: "batteryTime")
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

    func setHistoryDuration(seconds: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            let newLimit = max(10, min(600, seconds))
            guard newLimit != self.historyLimit else { return }
            self.historyLimit = newLimit
            for key in self.histories.keys {
                guard var values = self.histories[key], values.count > newLimit else { continue }
                values.removeFirst(values.count - newLimit)
                self.histories[key] = values
            }
        }
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
