import AVFoundation
import AppKit
import os.log

actor PermissionManager {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "PermissionManager")
    
    enum Permission {
        case microphone
        case accessibility
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
}
