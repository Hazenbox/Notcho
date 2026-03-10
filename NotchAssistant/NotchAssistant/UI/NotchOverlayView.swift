import SwiftUI

struct NotchContentView: View {
    @Bindable var viewModel: NotchViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(viewModel: viewModel)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            if viewModel.showOnboarding {
                OnboardingView(viewModel: viewModel)
            } else if viewModel.isLoadingModel {
                ModelLoadingView(progress: viewModel.modelDownloadProgress)
            } else {
                ContentScrollView(viewModel: viewModel)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                NotchFooterView(viewModel: viewModel)
            }
        }
        .frame(width: 420, height: 220)
        .background(Color.black)
        .onAppear {
            viewModel.setup()
        }
    }
}

struct HeaderView: View {
    @Bindable var viewModel: NotchViewModel
    @State private var isHoveringClose = false
    
    var body: some View {
        HStack {
            Text("Assistant")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            
            Spacer()
            
            Button(action: { viewModel.onHidePanel?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isHoveringClose ? .white : .white.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .background(isHoveringClose ? Color.white.opacity(0.15) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 8)
    }
}

struct ContentScrollView: View {
    @Bindable var viewModel: NotchViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.currentTranscript.isEmpty {
                    ListeningStatusView(isRunning: viewModel.isRunning)
                } else {
                    TranscriptView(transcript: viewModel.currentTranscript)
                }
                
                if let suggestion = viewModel.suggestion {
                    RecommendationView(
                        recommendation: suggestion.recommendation,
                        onCopy: { viewModel.copyToClipboard(suggestion.recommendation) }
                    )
                    .accessibilityIdentifier(AccessibilityIdentifiers.suggestionCard)
                } else if viewModel.isRunning && !viewModel.currentTranscript.isEmpty {
                    GeneratingView()
                }
                
                if case .error(let message) = viewModel.state {
                    ErrorView(message: message, onRetry: {
                        viewModel.clearError()
                        Task { await viewModel.startPipeline() }
                    })
                }
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 6)
        }
    }
}

struct ListeningStatusView: View {
    let isRunning: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isRunning ? "waveform" : "mic.slash")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
            
            Text(isRunning ? "Listening..." : "Not listening")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            
            Spacer()
            
            if !isRunning {
                Text("Click Start")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

struct TranscriptView: View {
    let transcript: String
    
    var body: some View {
        Text(transcript)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(AccessibilityIdentifiers.transcriptView)
    }
}

struct RecommendationView: View {
    let recommendation: String
    let onCopy: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("RECOMMENDATION")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                
                Spacer()
                
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isHovering ? .white : .white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .accessibilityIdentifier(AccessibilityIdentifiers.copyButton)
            }
            
            Text(recommendation)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GeneratingView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)
                .tint(.white)
            Text("Generating...")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 12))
            
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
            
            Spacer()
            
            Button(action: onRetry) {
                Text("Retry")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct NotchFooterView: View {
    @Bindable var viewModel: NotchViewModel
    @State private var isDemoRunning = false
    
    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                Task { await viewModel.togglePipeline() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 9))
                    Text(viewModel.isRunning ? "Stop" : "Start")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(viewModel.isRunning ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isRunning ? .red : .green)
            .accessibilityIdentifier(viewModel.isRunning ? AccessibilityIdentifiers.stopButton : AccessibilityIdentifiers.startButton)
            
            Spacer()
            
            Button(action: {
                isDemoRunning = true
                Task {
                    await viewModel.runDemoSimulation()
                    isDemoRunning = false
                }
            }) {
                HStack(spacing: 4) {
                    if isDemoRunning {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "play.circle")
                            .font(.system(size: 10))
                    }
                    Text("Demo")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .disabled(isDemoRunning)
            
            Button(action: {
                Task { await viewModel.requestSuggestion() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
            .accessibilityIdentifier(AccessibilityIdentifiers.regenerateButton)
            
            Button(action: { viewModel.copyAllSuggestions() }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
            .accessibilityIdentifier(AccessibilityIdentifiers.copyAllButton)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 6)
    }
}

struct ModelLoadingView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.white)
            
            Text("Loading Speech Model")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            
            if progress > 0 && progress < 1 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 120)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

#Preview {
    let viewModel = NotchViewModel()
    viewModel.loadMockData()
    return NotchContentView(viewModel: viewModel)
}
