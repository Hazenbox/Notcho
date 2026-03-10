import AppKit
import SwiftUI
import DynamicNotchKit

@MainActor
final class NotchWindowController {
    private var dynamicNotch: DynamicNotch<NotchContentView>?
    private let viewModel: NotchViewModel
    
    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }
    
    func setup() {
        dynamicNotch = DynamicNotch(style: .auto) { [viewModel] in
            NotchContentView(viewModel: viewModel)
        }
        
        viewModel.onHidePanel = { [weak self] in
            self?.hide()
        }
    }
    
    func show() {
        dynamicNotch?.show()
        
        if let panel = dynamicNotch?.windowController?.window as? NSPanel {
            panel.sharingType = .none
        }
    }
    
    func hide() {
        dynamicNotch?.hide(ignoreMouse: true)
    }
}
