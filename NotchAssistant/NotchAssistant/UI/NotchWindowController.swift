import AppKit
import SwiftUI

class ClickablePanel: NSPanel {
    var onMouseDown: (() -> Void)?
    
    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

@MainActor
final class NotchWindowController {
    private var panel: ClickablePanel!
    private let viewModel: NotchViewModel
    private var isExpanded = false
    private var clickOutsideMonitor: Any?
    
    // Consistent width for smooth vertical-only animation
    private let panelWidth: CGFloat = 580
    
    var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }
    
    var notchWidth: CGFloat {
        guard let screen = NSScreen.main else { return 180 }
        if #available(macOS 12.0, *) {
            if let leftArea = screen.auxiliaryTopLeftArea,
               let rightArea = screen.auxiliaryTopRightArea {
                return screen.frame.width - leftArea.width - rightArea.width
            }
        }
        return 180
    }
    
    var notchHeight: CGFloat {
        guard let screen = NSScreen.main else { return 32 }
        return screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32
    }
    
    private var collapsedHeight: CGFloat {
        notchHeight + 24
    }
    
    private var expandedHeight: CGFloat {
        230
    }
    
    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }
    
    func setup() {
        let contentView = NotchOverlayView(
            viewModel: viewModel,
            notchWidth: notchWidth,
            notchHeight: notchHeight
        )
        let hostingView = NSHostingView(rootView: contentView)
        
        panel = ClickablePanel(
            contentRect: collapsedFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .screenSaver
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.contentView = hostingView
        
        panel.onMouseDown = { [weak self] in
            guard let self = self else { return }
            if !self.isExpanded {
                self.expand()
            }
        }
        
        viewModel.onExpandToggle = { [weak self] in
            self?.toggle()
        }
        
        viewModel.onHidePanel = { [weak self] in
            self?.hide()
        }
    }
    
    func show() {
        panel.orderFront(nil)
    }
    
    func hide() {
        if isExpanded {
            collapse()
        }
        panel.orderOut(nil)
        removeClickOutsideMonitor()
    }
    
    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }
    
    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        viewModel.isExpanded = true
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
            panel.animator().setFrame(expandedFrame(), display: true)
        })
        
        setupClickOutsideMonitor()
    }
    
    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        viewModel.isExpanded = false
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1)
            panel.animator().setFrame(collapsedFrame(), display: true)
        })
        
        removeClickOutsideMonitor()
    }
    
    private func setupClickOutsideMonitor() {
        removeClickOutsideMonitor()
        
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isExpanded else { return }
            
            let mouseLocation = NSEvent.mouseLocation
            let panelFrame = self.panel.frame
            
            if !panelFrame.contains(mouseLocation) {
                Task { @MainActor in
                    self.collapse()
                }
            }
        }
    }
    
    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
    
    private func collapsedFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame
        
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - collapsedHeight
        
        return NSRect(x: x, y: y, width: panelWidth, height: collapsedHeight)
    }
    
    private func expandedFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame
        
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - expandedHeight
        
        return NSRect(x: x, y: y, width: panelWidth, height: expandedHeight)
    }
}
