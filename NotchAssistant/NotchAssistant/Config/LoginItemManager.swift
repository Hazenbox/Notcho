import ServiceManagement
import os.log

enum LoginItemManager {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "LoginItem")
    
    static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("Registered as login item")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Unregistered as login item")
            }
        } catch {
            logger.error("Failed to update login item: \(error.localizedDescription)")
        }
    }
    
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
