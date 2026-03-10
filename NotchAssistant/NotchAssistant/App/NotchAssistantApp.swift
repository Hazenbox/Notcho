import SwiftUI
import AppKit

@main
struct NotchAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Window("Utility", id: "utility") {
            SettingsHandlerView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .defaultSize(width: 0, height: 0)
        
        Settings {
            SettingsView()
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
    }
}

struct SettingsHandlerView: View {
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                DispatchQueue.main.async {
                    NSApp.windows.first { $0.identifier?.rawValue == "utility" }?.close()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                Task { @MainActor in
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
            }
    }
}

extension Notification.Name {
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
}
