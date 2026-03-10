import SwiftUI

@main
struct NotchAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)
    }
}
