import AppKit
import SwiftUI

class ClickablePanel: NSPanel {
    var onMouseDown: (() -> Void)?
    
    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

@MainActor
final class NotchWindowController {
    private var panel: ClickablePanel!
    private let viewModel: NotchViewModel
    private var isExpanded = false
    
    var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }
    
    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }
    
    func setup() {
        let contentView = NotchOverlayView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: contentView)
        
        panel = ClickablePanel(
            contentRect: collapsedFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .statusBar + 1
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
    }
    
    func show() {
        panel.orderFront(nil)
    }
    
    func hide() {
        panel.orderOut(nil)
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
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(expandedFrame(), display: true)
        }
    }
    
    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        viewModel.isExpanded = false
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(collapsedFrame(), display: true)
        }
    }
    
    private func collapsedFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame
        
        let width: CGFloat = 700
        let height: CGFloat = 140
        
        let x = screenFrame.midX - width / 2
        let y: CGFloat
        
        if hasNotch {
            let safeTop = screen.safeAreaInsets.top
            y = screenFrame.maxY - safeTop - height
        } else {
            y = screenFrame.maxY - 40 - height
        }
        
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    private func expandedFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame
        
        let width: CGFloat = 700
        let height: CGFloat = 460
        
        let x = screenFrame.midX - width / 2
        let y: CGFloat
        
        if hasNotch {
            let safeTop = screen.safeAreaInsets.top
            y = screenFrame.maxY - safeTop - height
        } else {
            y = screenFrame.maxY - 40 - height
        }
        
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
