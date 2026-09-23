import AppKit
import AudioToolbox
import CoreGraphics
import Foundation
import TouchingBarCore

enum MediaPlaybackController {
    static func perform(_ command: MediaCommand) {
        if NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.netease.163music"
        }) {
            let mediaRemoteCommand: Int
            switch command {
            case .previous: mediaRemoteCommand = 5
            case .playPause: mediaRemoteCommand = 2
            case .next: mediaRemoteCommand = 4
            }
            if MediaRemoteNowPlayingClient().send(command: mediaRemoteCommand) {
                return
            }
        }

        let target = preferredPlayer()
        let action: String
        switch command {
        case .previous: action = "previous track"
        case .playPause: action = "playpause"
        case .next: action = "next track"
        }
        guard let target else { return }
        runAppleScript("tell application \"\(target)\" to \(action)")
    }

    private static func preferredPlayer() -> String? {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.localizedName)
        if running.contains("Spotify") { return "Spotify" }
        if running.contains("Music") { return "Music" }
        return nil
    }

    private static func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            try? process.run()
        }
    }
}

enum SystemControlController {
    static func performVolume(_ command: VolumeCommand) {
        let current = systemVolume()
        switch command {
        case .mute:
            setMuted(!isMuted())
        case .down:
            setSystemVolume(max(0, current - 0.0625))
        case .up:
            setSystemVolume(min(1, current + 0.0625))
        }
    }

    static func adjustBrightness(direction: String) {
        typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSymbol = dlsym(handle, "DisplayServicesSetBrightness") else {
            return
        }
        defer { dlclose(handle) }

        let getBrightness = unsafeBitCast(getSymbol, to: GetBrightness.self)
        let setBrightness = unsafeBitCast(setSymbol, to: SetBrightness.self)
        var current: Float = 0.5
        let display = CGMainDisplayID()
        guard getBrightness(display, &current) == 0 else { return }
        let delta: Float = direction == "down" ? -0.0625 : 0.0625
        _ = setBrightness(display, min(1, max(0, current + delta)))
    }

    static func openFocusSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return nil
        }
        return deviceID
    }

    private static func systemVolume() -> Float {
        guard let deviceID = defaultOutputDevice() else { return 0.5 }
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var volume: Float = 0
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr {
                return volume
            }
        }
        return 0.5
    }

    private static func setSystemVolume(_ volume: Float) {
        guard let deviceID = defaultOutputDevice() else { return }
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var value = volume
            if AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float>.size),
                &value
            ) == noErr {
                return
            }
        }
    }

    private static func isMuted() -> Bool {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &size, &deviceID) == noErr else {
            return false
        }
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &muted) == noErr else {
            return false
        }
        return muted != 0
    }

    private static func setMuted(_ muted: Bool) {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &size, &deviceID) == noErr else {
            return
        }
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(
            deviceID,
            &muteAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
    }
}
