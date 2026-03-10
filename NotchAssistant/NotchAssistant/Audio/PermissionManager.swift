import AVFoundation
import AppKit
import ScreenCaptureKit
import os.log

actor PermissionManager {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "PermissionManager")
    
    enum Permission {
        case microphone
        case accessibility
        case screenRecording
    }
    
    enum PermissionStatus {
        case granted
        case denied
        case undetermined
    }
    
    func checkMicrophonePermission() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }
    
    func requestMicrophonePermission() async -> Bool {
        let status = checkMicrophonePermission()
        
        switch status {
        case .granted:
            return true
        case .denied:
            await showMicrophoneSettingsAlert()
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Self.logger.info("Microphone permission: \(granted ? "granted" : "denied")")
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    @MainActor
    private func showMicrophoneSettingsAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Microphone Access Required")
        alert.informativeText = String(localized: "Notch Assistant needs microphone access to listen to meeting audio. Please enable microphone access in System Settings > Privacy & Security > Microphone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Open Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    func checkAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    func requestAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    func checkScreenRecordingPermission() async -> PermissionStatus {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return .granted
        } catch {
            let nsError = error as NSError
            if nsError.code == -3801 {
                return .denied
            }
            return .undetermined
        }
    }
    
    func requestScreenRecordingPermission() async -> Bool {
        let status = await checkScreenRecordingPermission()
        
        switch status {
        case .granted:
            return true
        case .denied:
            await showScreenRecordingSettingsAlert()
            return false
        case .undetermined:
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                await showRestartRequiredAlert()
                return false
            } catch {
                await showScreenRecordingSettingsAlert()
                return false
            }
        }
    }
    
    @MainActor
    private func showScreenRecordingSettingsAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Screen Recording Access Required")
        alert.informativeText = String(localized: "Notch Assistant needs Screen Recording access to capture meeting audio from Zoom, Meet, Teams and other apps. Please enable it in System Settings > Privacy & Security > Screen Recording.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Open Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @MainActor
    private func showRestartRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Restart Required")
        alert.informativeText = String(localized: "Screen Recording permission has been granted. Please restart Notch Assistant to enable system audio capture.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Restart Now"))
        alert.addButton(withTitle: String(localized: "Later"))
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
            let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [path]
            task.launch()
            NSApp.terminate(nil)
        }
    }
}
