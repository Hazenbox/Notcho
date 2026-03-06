import SwiftUI

struct OnboardingView: View {
    @Bindable var viewModel: NotchViewModel
    @State private var apiKey: String = ""
    @State private var currentStep = 0
    @State private var isDownloadingModel = false
    @State private var downloadProgress: Double = 0
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to Notch Assistant")
                .font(.system(.title2, weight: .bold))
            
            TabView(selection: $currentStep) {
                welcomeStep
                    .tag(0)
                
                apiKeyStep
                    .tag(1)
                
                permissionsStep
                    .tag(2)
            }
            .tabViewStyle(.automatic)
            
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button(currentStep == 2 ? "Get Started" : "Continue") {
                    if currentStep == 2 {
                        completeOnboarding()
                    } else {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentStep == 1 && apiKey.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400, height: 450)
    }
    
    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            
            Text("Your AI Meeting Copilot")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "ear", text: "Listens to your meetings")
                FeatureRow(icon: "text.bubble", text: "Transcribes in real-time")
                FeatureRow(icon: "lightbulb", text: "Suggests responses & questions")
            }
            .padding(.top, 8)
        }
        .padding()
    }
    
    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text("Claude API Key")
                .font(.headline)
            
            Text("Enter your Anthropic API key to enable AI suggestions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            SecureField("sk-ant-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
            
            Link("Get your API key from Anthropic", destination: URL(string: "https://console.anthropic.com/")!)
                .font(.caption)
        }
        .padding()
    }
    
    private var permissionsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            
            Text("Permissions")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    icon: "mic",
                    title: "Microphone",
                    description: "To capture meeting audio"
                )
                
                PermissionRow(
                    icon: "lock.shield",
                    title: "Privacy",
                    description: "Transcripts stay in memory only"
                )
            }
            .padding(.top, 8)
            
            Text("You'll be prompted for microphone access when you start listening.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private func completeOnboarding() {
        if !apiKey.isEmpty {
            viewModel.saveAPIKey(apiKey)
        }
        viewModel.showOnboarding = false
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let viewModel = NotchViewModel()
    return OnboardingView(viewModel: viewModel)
}
