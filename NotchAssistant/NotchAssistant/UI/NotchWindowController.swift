import AppKit
import SwiftUI

@MainActor
final class NotchWindowController {
    private var panel: NSPanel!
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
        
        panel = NSPanel(
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
        
        // Setup click handler for expand/collapse
        setupClickHandler()
        
        // Observe view model for expansion state
        viewModel.onExpandToggle = { [weak self] in
            self?.toggle()
        }
    }
    
    private func setupClickHandler() {
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        panel.contentView?.addGestureRecognizer(clickGesture)
    }
    
    @objc private func handleClick() {
        toggle()
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
        
        let width: CGFloat = 200
        let height: CGFloat = 32
        
        if hasNotch {
            let safeTop = screen.safeAreaInsets.top
            let x = screenFrame.midX - width / 2
            let y = screenFrame.maxY - safeTop - height + 4
            return NSRect(x: x, y: y, width: width, height: height)
        } else {
            let x = screenFrame.midX - width / 2
            let y = screenFrame.maxY - 60
            return NSRect(x: x, y: y, width: width, height: height)
        }
    }
    
    private func expandedFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame
        
        let width: CGFloat = 340
        let height: CGFloat = 460
        
        let x = screenFrame.midX - width / 2
        let y: CGFloat
        
        if hasNotch {
            y = screenFrame.maxY - screen.safeAreaInsets.top - height + 4
        } else {
            y = screenFrame.maxY - 60 - height + 32
        }
        
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
