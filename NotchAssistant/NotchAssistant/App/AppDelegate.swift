import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notchWindowController: NotchWindowController?
    private var viewModel: NotchViewModel?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check hardware requirements
        HardwareChecker.verifyOrExit()
        
        // Hide dock icon (menu bar app)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup status bar item
        setupStatusBar()
        
        // Setup notch overlay
        setupNotchOverlay()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Notch Assistant")
            button.action = #selector(statusBarClicked)
            button.target = self
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: String(localized: "Show Assistant"), action: #selector(showAssistant), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: String(localized: "Hide Assistant"), action: #selector(hideAssistant), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Settings..."), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit"), action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    private func setupNotchOverlay() {
        viewModel = NotchViewModel()
        notchWindowController = NotchWindowController(viewModel: viewModel!)
        notchWindowController?.setup()
        notchWindowController?.show()
    }
    
    @objc private func statusBarClicked() {
        notchWindowController?.toggle()
    }
    
    @objc private func showAssistant() {
        notchWindowController?.show()
    }
    
    @objc private func hideAssistant() {
        notchWindowController?.hide()
    }
    
    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
