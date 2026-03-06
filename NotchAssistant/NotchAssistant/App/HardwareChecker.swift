import AppKit

enum HardwareChecker {
    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    
    static func verifyOrExit() {
        guard isAppleSilicon else {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = String(localized: "Unsupported Hardware")
                alert.informativeText = String(localized: "Notch Assistant requires a Mac with Apple Silicon (M1 or later) for real-time transcription.\n\nThis app uses on-device AI models that are optimized for Apple Silicon's Neural Engine.")
                alert.alertStyle = .critical
                alert.addButton(withTitle: String(localized: "Quit"))
                alert.runModal()
                NSApplication.shared.terminate(nil)
            }
            return
        }
    }
}
