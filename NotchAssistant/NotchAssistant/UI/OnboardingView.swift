import SwiftUI

struct OnboardingView: View {
    @Bindable var viewModel: NotchViewModel
    @State private var apiKey: String = ""
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                
                Text("Enter Claude API Key")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            SecureField("sk-ant-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            
            HStack(spacing: 8) {
                Link("Get API key", destination: URL(string: "https://console.anthropic.com/")!)
                    .font(.system(size: 11))
                
                Spacer()
                
                Button("Save") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(apiKey.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func completeOnboarding() {
        guard !apiKey.isEmpty else { return }
        viewModel.saveAPIKey(apiKey)
        viewModel.showOnboarding = false
        Task { await viewModel.startPipeline() }
    }
}

#Preview {
    let viewModel = NotchViewModel()
    return OnboardingView(viewModel: viewModel)
        .frame(width: 380, height: 100)
        .background(Color.black)
}
