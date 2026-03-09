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
        
        viewModel.onExpandToggle = { [weak self] in
            self?.toggle()
        }
        
        viewModel.onHidePanel = { [weak self] in
            self?.hide()
        }
    }
    
    func show() {
        dynamicNotch?.show()
        viewModel.isExpanded = true
    }
    
    func hide() {
        dynamicNotch?.hide()
        viewModel.isExpanded = false
    }
    
    func toggle() {
        if viewModel.isExpanded {
            hide()
        } else {
            show()
        }
    }
}
