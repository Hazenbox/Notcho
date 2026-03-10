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
    }
    
    func hide() {
        dynamicNotch?.hide(ignoreMouse: true)
    }
}
