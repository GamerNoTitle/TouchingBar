import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration
import TouchingBarCore

/// Low-frequency, utility-queue sampling. No network probes unless a visible latency item requests one.
final class NetworkStatusService {
    private let queue = DispatchQueue(label: "app.touchingbar.network-status", qos: .utility)
    private let stateLock = NSLock()
    private var timer: DispatchSourceTimer?
    private var hosts: [String] = []
    private var generation = 0
    private var running = false

    func start(handler: @escaping (NetworkStatusSnapshot) -> Void) {
        stateLock.lock()
        guard !running else { stateLock.unlock(); return }
        running = true
        stateLock.unlock()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 10, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in self?.sample(handler: handler) }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        stateLock.lock()
        running = false
        generation += 1
        hosts = []
        stateLock.unlock()
        timer?.cancel()
        timer = nil
    }

    func setActiveProbeHosts(_ requested: [String]) {
        let normalized = Array(Set(requested.compactMap { NetworkStatusSnapshot.normalizedProbeHost($0) })).sorted()
        stateLock.lock()
        // Bound resource use even with an imported configuration containing many hosts.
        let bounded = Array(normalized.prefix(4))
        if hosts != bounded { hosts = bounded; generation += 1 }
        stateLock.unlock()
    }

    private func isCurrent(_ expected: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running && generation == expected
    }

    private func sample(handler: @escaping (NetworkStatusSnapshot) -> Void) {
        stateLock.lock()
        let requestedHosts = hosts
        let expected = generation
        let active = running
        stateLock.unlock()
        guard active else { return }
        var snapshot = Self.identitySnapshot()
        for host in requestedHosts {
            guard isCurrent(expected) else { return }
            snapshot.latencyByHost[host] = probe(host: host, generation: expected)
        }
        guard isCurrent(expected) else { return }
        DispatchQueue.main.async { [weak self] in
            guard self?.isCurrent(expected) == true else { return }
            handler(snapshot)
        }
    }

    private static func identitySnapshot() -> NetworkStatusSnapshot {
        var result = NetworkStatusSnapshot()
        if let interface = CWWiFiClient.shared().interface() {
            if !interface.powerOn() {
                result.wifiState = .poweredOff
            } else if let ssid = interface.ssid(), !ssid.isEmpty {
                result.wifiState = .connected
                result.wifiSSID = ssid
            } else {
                // CoreWLAN hides SSID without location authorization on recent macOS.
                // A nil SSID cannot safely distinguish that from disconnection.
                result.wifiState = .ssidUnavailable
            }
        } else {
            result.wifiState = .unavailable
        }

        guard let store = SCDynamicStoreCreate(nil, "TouchingBar.NetworkStatus" as CFString, nil, nil) else { return result }
        let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let primary = global?["PrimaryInterface"] as? String
        let ipv4Keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Interface/.*/IPv4" as CFString) as? [String] ?? []
        let ipv6Keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Interface/.*/IPv6" as CFString) as? [String] ?? []
        let keys = (ipv4Keys + ipv6Keys).sorted { left, right in
            let leftPrimary = primary.map { left.contains("/\($0)/") } ?? false
            let rightPrimary = primary.map { right.contains("/\($0)/") } ?? false
            if leftPrimary != rightPrimary { return leftPrimary }
            if left.hasSuffix("IPv4") != right.hasSuffix("IPv4") { return left.hasSuffix("IPv4") }
            return left < right
        }
        for key in keys where !key.contains("/lo0/") {
            let state = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
            if let address = (state?["Addresses"] as? [String])?.first(where: {
                !$0.hasPrefix("127.") && $0 != "::1" && !$0.hasPrefix("fe80:") && !$0.hasPrefix("169.254.")
            }) {
                result.localIP = address
                break
            }
        }
        // Interface names are a heuristic: utun is also used by non-VPN Apple services.
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&interfaces) == 0 {
            defer { freeifaddrs(interfaces) }
            var cursor = interfaces
            var tunnel = false
            while let entry = cursor {
                let name = String(cString: entry.pointee.ifa_name)
                let up = entry.pointee.ifa_flags & UInt32(IFF_UP) != 0
                if up && ["utun", "tun", "tap", "ppp", "ipsec"].contains(where: { name.hasPrefix($0) }) { tunnel = true }
                cursor = entry.pointee.ifa_next
            }
            result.vpnState = tunnel ? .tunnelDetected : .noTunnelDetected
        }
        return result
    }

    private func probe(host: String, generation expected: Int) -> NetworkStatusSnapshot.LatencyResult {
        let process = Process()
        let output = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: host.contains(":") ? "/sbin/ping6" : "/sbin/ping")
        process.arguments = ["-n", "-c", "1", host]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return .unavailable }
        let deadline = Date().addingTimeInterval(3)
        var exited = false
        while Date() < deadline && isCurrent(expected) {
            if finished.wait(timeout: .now() + 0.1) == .success { exited = true; break }
        }
        if !exited {
            // SIGKILL bounds DNS-resolution stalls too; never wait indefinitely on a subprocess.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            _ = finished.wait(timeout: .now() + 0.5)
            return .unavailable
        }
        guard process.terminationStatus == 0 else { return .unavailable }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8),
              let match = text.range(of: "time[=<]([0-9]+(?:\\.[0-9]+)?)", options: .regularExpression) else { return .unavailable }
        let number = text[match].dropFirst(5)
        guard let milliseconds = Double(number), milliseconds.isFinite, milliseconds >= 0 else { return .unavailable }
        return .milliseconds(milliseconds)
    }
}
