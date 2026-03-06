import Foundation
import AppKit
import os.log

actor MeetingDetector: MeetingDetecting {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "MeetingDetector")
    
    private var _isMeetingActive = false
    private var lastActiveApp: String?
    
    private let meetingApps = Set([
        "com.apple.FaceTime",
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.google.Chrome",
        "com.brave.Browser",
        "com.apple.Safari",
        "com.microsoft.Outlook",
        "com.webex.meetingmanager",
        "com.cisco.webexmeetingsapp",
        "com.slack.Slack",
        "com.discord.Discord",
        "com.loom.desktop"
    ])
    
    private let meetingWindowTitles = [
        "zoom",
        "meeting",
        "call",
        "webex",
        "teams",
        "meet",
        "huddle",
        "standup"
    ]
    
    var isMeetingActive: Bool {
        _isMeetingActive
    }
    
    func detectActiveMeeting() async -> Bool {
        let activeApp = await getActiveApplication()
        
        if let bundleId = activeApp?.bundleIdentifier {
            if meetingApps.contains(bundleId) {
                Self.logger.debug("Meeting app detected: \(bundleId)")
                _isMeetingActive = true
                lastActiveApp = bundleId
                return true
            }
        }
        
        if let windowTitle = activeApp?.localizedName?.lowercased() {
            for keyword in meetingWindowTitles {
                if windowTitle.contains(keyword) {
                    Self.logger.debug("Meeting keyword in window title: \(windowTitle)")
                    _isMeetingActive = true
                    return true
                }
            }
        }
        
        _isMeetingActive = false
        return false
    }
    
    @MainActor
    private func getActiveApplication() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }
    
    func startMonitoring() {
        Task { @MainActor in
            let center = NSWorkspace.shared.notificationCenter
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task {
                    _ = await self?.detectActiveMeeting()
                }
            }
        }
        
        Self.logger.info("Started meeting detection monitoring")
    }
    
    func stopMonitoring() {
        Task { @MainActor in
            let center = NSWorkspace.shared.notificationCenter
            center.removeObserver(self)
        }
        
        Self.logger.info("Stopped meeting detection monitoring")
    }
}
