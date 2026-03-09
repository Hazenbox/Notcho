import SwiftUI

struct NotchCutoutShape: Shape {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let notchCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    
    init(notchWidth: CGFloat, notchHeight: CGFloat, notchCornerRadius: CGFloat = 8, bottomCornerRadius: CGFloat = 20) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.notchCornerRadius = notchCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let notchLeft = midX - notchWidth / 2
        let notchRight = midX + notchWidth / 2
        let ncr = notchCornerRadius
        let bcr = bottomCornerRadius
        
        path.move(to: CGPoint(x: 0, y: 0))
        
        path.addLine(to: CGPoint(x: notchLeft - ncr, y: 0))
        
        path.addQuadCurve(
            to: CGPoint(x: notchLeft, y: ncr),
            control: CGPoint(x: notchLeft, y: 0)
        )
        
        path.addLine(to: CGPoint(x: notchLeft, y: notchHeight - ncr))
        
        path.addQuadCurve(
            to: CGPoint(x: notchLeft + ncr, y: notchHeight),
            control: CGPoint(x: notchLeft, y: notchHeight)
        )
        
        path.addLine(to: CGPoint(x: notchRight - ncr, y: notchHeight))
        
        path.addQuadCurve(
            to: CGPoint(x: notchRight, y: notchHeight - ncr),
            control: CGPoint(x: notchRight, y: notchHeight)
        )
        
        path.addLine(to: CGPoint(x: notchRight, y: ncr))
        
        path.addQuadCurve(
            to: CGPoint(x: notchRight + ncr, y: 0),
            control: CGPoint(x: notchRight, y: 0)
        )
        
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bcr))
        
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bcr, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        
        path.addLine(to: CGPoint(x: bcr, y: rect.maxY))
        
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY - bcr),
            control: CGPoint(x: 0, y: rect.maxY)
        )
        
        path.addLine(to: CGPoint(x: 0, y: 0))
        
        return path
    }
}

struct NotchOverlayView: View {
    @Bindable var viewModel: NotchViewModel
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    
    init(viewModel: NotchViewModel, notchWidth: CGFloat = 180, notchHeight: CGFloat = 32) {
        self.viewModel = viewModel
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            if viewModel.showOnboarding {
                OnboardingView(viewModel: viewModel)
            } else if viewModel.isLoadingModel {
                ModelLoadingView(progress: viewModel.modelDownloadProgress)
            } else if viewModel.isExpanded {
                ExpandedContentView(viewModel: viewModel, notchWidth: notchWidth, notchHeight: notchHeight)
            } else {
                CollapsedContentView(viewModel: viewModel, notchWidth: notchWidth, notchHeight: notchHeight)
            }
        }
        .clipShape(NotchCutoutShape(notchWidth: notchWidth, notchHeight: notchHeight))
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        .onAppear {
            viewModel.setup()
        }
    }
}

struct ModelLoadingView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(0.9)
                .tint(.white)
            
            Text("Loading Speech Model")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            
            if progress > 0 && progress < 1 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 140)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Loading speech model"))
        .accessibilityValue(progress > 0 ? "\(Int(progress * 100)) percent" : "Starting")
    }
}

struct NotchCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isHovering ? .white : .white.opacity(0.5))
                .frame(width: 24, height: 24)
                .background(isHovering ? Color.white.opacity(0.2) : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(String(localized: "Close panel"))
    }
}

struct CollapsedContentView: View {
    @Bindable var viewModel: NotchViewModel
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    
    var body: some View {
        HStack(spacing: 0) {
            Text("Assistant")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.leading, 16)
            
            Spacer()
                .frame(width: notchWidth + 16)
            
            NotchCloseButton(action: { viewModel.onHidePanel?() })
                .padding(.trailing, 12)
        }
        .frame(height: notchHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Notch Assistant"))
        .accessibilityHint(String(localized: "Click to expand"))
        .accessibilityIdentifier(AccessibilityIdentifiers.statusIndicator)
    }
}

struct ExpandedContentView: View {
    @Bindable var viewModel: NotchViewModel
    @FocusState private var focusedElement: FocusableElement?
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    
    enum FocusableElement: Hashable {
        case transcript, suggestion, question, insight, regenerate, copyAll, close
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Assistant")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.leading, 16)
                
                Spacer()
                    .frame(width: notchWidth + 16)
                
                NotchCloseButton(action: { viewModel.onHidePanel?() })
                    .accessibilityIdentifier(AccessibilityIdentifiers.closeButton)
                    .padding(.trailing, 12)
            }
            .frame(height: notchHeight)
            
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            
            if case .error(let message) = viewModel.state {
                ErrorBannerView(message: message, onRetry: {
                    viewModel.clearError()
                    Task {
                        await viewModel.startPipeline()
                    }
                })
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.currentTranscript.isEmpty {
                        EmptyTranscriptView(isRunning: viewModel.isRunning)
                    } else {
                        TranscriptSectionView(transcript: viewModel.currentTranscript)
                            .focused($focusedElement, equals: .transcript)
                    }
                    
                    if !viewModel.currentTopic.isEmpty {
                        TopicView(topic: viewModel.currentTopic)
                    }
                    
                    if let suggestion = viewModel.suggestion {
                        SuggestionCardView(
                            title: String(localized: "SUGGESTION"),
                            content: suggestion.suggestion,
                            onCopy: { viewModel.copyToClipboard(suggestion.suggestion) }
                        )
                        .focused($focusedElement, equals: .suggestion)
                        .accessibilityIdentifier(AccessibilityIdentifiers.suggestionCard)
                        
                        SuggestionCardView(
                            title: String(localized: "QUESTION"),
                            content: suggestion.question,
                            onCopy: { viewModel.copyToClipboard(suggestion.question) }
                        )
                        .focused($focusedElement, equals: .question)
                        .accessibilityIdentifier(AccessibilityIdentifiers.questionCard)
                        
                        InsightCardView(
                            content: suggestion.insight
                        )
                        .focused($focusedElement, equals: .insight)
                        .accessibilityIdentifier(AccessibilityIdentifiers.insightCard)
                    } else if viewModel.isRunning && !viewModel.currentTranscript.isEmpty {
                        WaitingForSuggestionView()
                    }
                }
                .padding(16)
            }
            
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 16)
            
            FooterView(viewModel: viewModel)
        }
        .onKeyPress(.escape) {
            viewModel.onExpandToggle?()
            return .handled
        }
        .onKeyPress(.tab) {
            advanceFocus()
            return .handled
        }
    }
    
    private func advanceFocus() {
        switch focusedElement {
        case .transcript: focusedElement = .suggestion
        case .suggestion: focusedElement = .question
        case .question: focusedElement = .insight
        case .insight: focusedElement = .regenerate
        case .regenerate: focusedElement = .copyAll
        case .copyAll: focusedElement = .close
        case .close, .none: focusedElement = .transcript
        }
    }
}

struct ErrorBannerView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14))
            
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(2)
            
            Spacer()
            
            Button(action: onRetry) {
                Text("Retry")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.red.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
        .accessibilityHint("Tap retry to try again")
    }
}

struct EmptyTranscriptView: View {
    let isRunning: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isRunning ? "waveform" : "mic.slash")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.4))
            
            Text(isRunning ? "Listening..." : "Not listening")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            
            if !isRunning {
                Text("Click Start to begin")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isRunning ? "Listening for speech" : "Not listening. Click start to begin.")
    }
}

struct WaitingForSuggestionView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(.white)
            
            Text("Generating suggestions...")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct TranscriptSectionView: View {
    let transcript: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRANSCRIPT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            
            Text(transcript)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(white: 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Transcript"))
        .accessibilityValue(transcript)
        .accessibilityIdentifier(AccessibilityIdentifiers.transcriptView)
    }
}

struct TopicView: View {
    let topic: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text("TOPIC:")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            
            Text(topic)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Current topic"))
        .accessibilityValue(topic)
    }
}

struct SuggestionCardView: View {
    let title: String
    let content: String
    let onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                
                Spacer()
                
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Copy to clipboard"))
                .accessibilityHint(String(localized: "Copies this suggestion to your clipboard"))
                .accessibilityIdentifier(AccessibilityIdentifiers.copyButton)
            }
            
            Text(content)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(content)
    }
}

struct InsightCardView: View {
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INSIGHT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            
            Text(content)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Insight"))
        .accessibilityValue(content)
    }
}

struct FooterView: View {
    @Bindable var viewModel: NotchViewModel
    @State private var isDemoRunning = false
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: {
                Task {
                    await viewModel.togglePipeline()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 12))
                    Text(viewModel.isRunning ? "Stop" : "Start")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(viewModel.isRunning ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isRunning ? .red : .green)
            .accessibilityLabel(viewModel.isRunning ? String(localized: "Stop listening") : String(localized: "Start listening"))
            .accessibilityIdentifier(viewModel.isRunning ? AccessibilityIdentifiers.stopButton : AccessibilityIdentifiers.startButton)
            
            Spacer()
            
            Button(action: {
                isDemoRunning = true
                Task {
                    await viewModel.runDemoSimulation()
                    isDemoRunning = false
                }
            }) {
                HStack(spacing: 6) {
                    if isDemoRunning {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "play.circle")
                            .font(.system(size: 12))
                    }
                    Text("Demo")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .disabled(isDemoRunning)
            .accessibilityLabel("Run demo simulation")
            .help("Simulates: 'What is design thinking?'")
            
            Button(action: {
                Task {
                    await viewModel.requestSuggestion()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                    Text("Regenerate")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .accessibilityLabel(String(localized: "Regenerate suggestions"))
            .accessibilityIdentifier(AccessibilityIdentifiers.regenerateButton)
            
            Button(action: { viewModel.copyAllSuggestions() }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                    Text("Copy All")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .accessibilityLabel(String(localized: "Copy all suggestions"))
            .accessibilityIdentifier(AccessibilityIdentifiers.copyAllButton)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct StatusIndicatorView: View {
    let state: PipelineState
    
    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .shadow(color: statusColor.opacity(0.6), radius: 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Status"))
            .accessibilityValue(accessibilityValue)
    }
    
    private var statusColor: Color {
        switch state {
        case .idle: return .gray
        case .listening: return .green
        case .processing: return .yellow
        case .error: return .red
        }
    }
    
    private var accessibilityValue: String {
        switch state {
        case .idle: return String(localized: "Not active")
        case .listening: return String(localized: "Actively listening to meeting audio")
        case .processing: return String(localized: "Processing audio and generating suggestions")
        case .error: return String(localized: "An error occurred")
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview("Collapsed") {
    let viewModel = NotchViewModel()
    viewModel.state = .listening
    return NotchOverlayView(viewModel: viewModel, notchWidth: 180, notchHeight: 32)
        .frame(width: 580, height: 55)
}

#Preview("Expanded") {
    let viewModel = NotchViewModel()
    viewModel.loadMockData()
    viewModel.isExpanded = true
    return NotchOverlayView(viewModel: viewModel, notchWidth: 180, notchHeight: 32)
        .frame(width: 600, height: 460)
}
