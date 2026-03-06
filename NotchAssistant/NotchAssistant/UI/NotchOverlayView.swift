import SwiftUI

struct NotchOverlayView: View {
    @Bindable var viewModel: NotchViewModel
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
            
            if viewModel.showOnboarding {
                OnboardingView(viewModel: viewModel)
            } else if viewModel.isLoadingModel {
                ModelLoadingView(progress: viewModel.modelDownloadProgress)
            } else if viewModel.isExpanded {
                ExpandedContentView(viewModel: viewModel)
            } else {
                CollapsedContentView(viewModel: viewModel)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: viewModel.isExpanded ? 16 : 20, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            viewModel.setup()
        }
    }
}

struct ModelLoadingView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Loading Speech Model")
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.primary)
            
            if progress > 0 && progress < 1 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Loading speech model"))
        .accessibilityValue(progress > 0 ? "\(Int(progress * 100)) percent" : "Starting")
    }
}

struct CollapsedContentView: View {
    @Bindable var viewModel: NotchViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            StatusIndicatorView(state: viewModel.state)
            
            Text(statusText)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Notch Assistant"))
        .accessibilityValue(statusText)
        .accessibilityHint(String(localized: "Click to expand"))
        .accessibilityIdentifier(AccessibilityIdentifiers.statusIndicator)
    }
    
    private var statusText: String {
        switch viewModel.state {
        case .idle: return String(localized: "Idle")
        case .listening: return String(localized: "Listening")
        case .processing: return String(localized: "Processing")
        case .error: return String(localized: "Error")
        }
    }
}

struct ExpandedContentView: View {
    @Bindable var viewModel: NotchViewModel
    @FocusState private var focusedElement: FocusableElement?
    
    enum FocusableElement: Hashable {
        case transcript, suggestion, question, insight, regenerate, copyAll, close
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HeaderView(viewModel: viewModel)
            
            Divider()
                .padding(.horizontal, 16)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Transcript section
                    TranscriptSectionView(transcript: viewModel.currentTranscript)
                        .focused($focusedElement, equals: .transcript)
                    
                    // Topic
                    if !viewModel.currentTopic.isEmpty {
                        TopicView(topic: viewModel.currentTopic)
                    }
                    
                    // Suggestions
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
                    }
                }
                .padding(16)
            }
            
            Divider()
                .padding(.horizontal, 16)
            
            // Footer actions
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

struct HeaderView: View {
    @Bindable var viewModel: NotchViewModel
    
    var body: some View {
        HStack {
            StatusIndicatorView(state: viewModel.state)
            
            Spacer()
            
            Button(action: { viewModel.onExpandToggle?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close"))
            .accessibilityIdentifier(AccessibilityIdentifiers.closeButton)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct TranscriptSectionView: View {
    let transcript: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TRANSCRIPT")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(.tertiary)
            
            Text(transcript)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        HStack(spacing: 6) {
            Text("TOPIC:")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(.tertiary)
            
            Text(topic)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.primary)
        }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Copy to clipboard"))
                .accessibilityHint(String(localized: "Copies this suggestion to your clipboard"))
                .accessibilityIdentifier(AccessibilityIdentifiers.copyButton)
            }
            
            Text(content)
                .font(.system(.body))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(content)
    }
}

struct InsightCardView: View {
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INSIGHT")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(.tertiary)
            
            Text(content)
                .font(.system(.callout))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Insight"))
        .accessibilityValue(content)
    }
}

struct FooterView: View {
    @Bindable var viewModel: NotchViewModel
    
    var body: some View {
        HStack {
            Button(action: {
                Task {
                    await viewModel.togglePipeline()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 11))
                    Text(viewModel.isRunning ? "Stop" : "Start")
                        .font(.system(.caption, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isRunning ? .red : .green)
            .accessibilityLabel(viewModel.isRunning ? String(localized: "Stop listening") : String(localized: "Start listening"))
            .accessibilityIdentifier(viewModel.isRunning ? AccessibilityIdentifiers.stopButton : AccessibilityIdentifiers.startButton)
            
            Spacer()
            
            Button(action: {
                Task {
                    await viewModel.requestSuggestion()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("Regenerate")
                        .font(.system(.caption, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: "Regenerate suggestions"))
            .accessibilityIdentifier(AccessibilityIdentifiers.regenerateButton)
            
            Spacer()
            
            Button(action: { viewModel.copyAllSuggestions() }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                    Text("Copy All")
                        .font(.system(.caption, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: "Copy all suggestions"))
            .accessibilityIdentifier(AccessibilityIdentifiers.copyAllButton)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct StatusIndicatorView: View {
    let state: PipelineState
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.5), radius: 4)
            
            Text(statusText)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.primary)
        }
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
    
    private var statusText: String {
        switch state {
        case .idle: return String(localized: "Idle")
        case .listening: return String(localized: "Listening")
        case .processing: return String(localized: "Processing")
        case .error: return String(localized: "Error")
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
    return NotchOverlayView(viewModel: viewModel)
        .frame(width: 200, height: 32)
}

#Preview("Expanded") {
    let viewModel = NotchViewModel()
    viewModel.loadMockData()
    viewModel.isExpanded = true
    return NotchOverlayView(viewModel: viewModel)
        .frame(width: 340, height: 460)
}
