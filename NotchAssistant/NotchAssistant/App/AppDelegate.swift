import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notchWindowController: NotchWindowController?
    private var viewModel: NotchViewModel?
    
    private var systemAudioItem: NSMenuItem?
    private var microphoneItem: NSMenuItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        HardwareChecker.verifyOrExit()
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        setupNotchOverlay()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Notch Assistant")
        }
        
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: String(localized: "Show Assistant"), action: #selector(showAssistant), keyEquivalent: "m"))
        menu.addItem(NSMenuItem.separator())
        
        let audioMenu = NSMenu()
        
        systemAudioItem = NSMenuItem(title: String(localized: "System Audio"), action: #selector(selectSystemAudio), keyEquivalent: "")
        systemAudioItem?.target = self
        if let item = systemAudioItem {
            audioMenu.addItem(item)
        }
        
        microphoneItem = NSMenuItem(title: String(localized: "Microphone"), action: #selector(selectMicrophone), keyEquivalent: "")
        microphoneItem?.target = self
        if let item = microphoneItem {
            audioMenu.addItem(item)
        }
        
        let audioSourceItem = NSMenuItem(title: String(localized: "Audio Source"), action: nil, keyEquivalent: "")
        audioSourceItem.submenu = audioMenu
        menu.addItem(audioSourceItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit"), action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        
        updateAudioSourceMenu()
    }
    
    private func setupNotchOverlay() {
        viewModel = NotchViewModel()
        guard let vm = viewModel else { return }
        notchWindowController = NotchWindowController(viewModel: vm)
        notchWindowController?.setup()
        notchWindowController?.show()
    }
    
    private func updateAudioSourceMenu() {
        let currentSource = UserDefaults.standard.string(forKey: "audioSource") ?? "system"
        systemAudioItem?.state = currentSource == "system" ? .on : .off
        microphoneItem?.state = currentSource == "microphone" ? .on : .off
    }
    
    @objc private func selectSystemAudio() {
        UserDefaults.standard.set("system", forKey: "audioSource")
        updateAudioSourceMenu()
    }
    
    @objc private func selectMicrophone() {
        UserDefaults.standard.set("microphone", forKey: "audioSource")
        updateAudioSourceMenu()
    }
    
    @objc private func showAssistant() {
        notchWindowController?.show()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
