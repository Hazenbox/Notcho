import SwiftUI

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("analyticsEnabled") private var analyticsEnabled: Bool = true
    @AppStorage("selectedModel") private var selectedModel: String = "claude-3-haiku-20240307"
    @AppStorage("audioSource") private var audioSource: String = "system"
    
    var body: some View {
        TabView {
            GeneralSettingsView(launchAtLogin: $launchAtLogin)
                .tabItem {
                    Label(String(localized: "General"), systemImage: "gear")
                }
            
            AudioSettingsView(audioSource: $audioSource)
                .tabItem {
                    Label(String(localized: "Audio"), systemImage: "waveform")
                }
            
            APISettingsView(selectedModel: $selectedModel)
                .tabItem {
                    Label(String(localized: "API"), systemImage: "key")
                }
            
            PrivacySettingsView(analyticsEnabled: $analyticsEnabled)
                .tabItem {
                    Label(String(localized: "Privacy"), systemImage: "hand.raised")
                }
        }
        .frame(width: 480, height: 360)
    }
}

struct GeneralSettingsView: View {
    @Binding var launchAtLogin: Bool
    
    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItemManager.setLaunchAtLogin(newValue)
                    }
            } header: {
                Text("Startup")
            }
            
            Section {
                LabeledContent(String(localized: "Keyboard Shortcut")) {
                    Text("Option + Space")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Controls")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct APISettingsView: View {
    @Binding var selectedModel: String
    @State private var apiKey: String = ""
    @State private var showingKey = false
    @State private var hasKey = false
    
    private let models = [
        ("claude-3-haiku-20240307", "Claude 3 Haiku (Fast, Cost-effective)"),
        ("claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet (Quality)")
    ]
    
    var body: some View {
        Form {
            Section {
                HStack {
                    if showingKey {
                        TextField(String(localized: "API Key"), text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: apiKey) { _, newValue in
                                saveAPIKey(newValue)
                            }
                    } else {
                        SecureField(String(localized: "API Key"), text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: apiKey) { _, newValue in
                                saveAPIKey(newValue)
                            }
                    }
                    
                    Button(action: { showingKey.toggle() }) {
                        Image(systemName: showingKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(showingKey ? "Hide API key" : "Show API key")
                }
                
                if hasKey {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("API key saved securely in Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Picker(String(localized: "Model"), selection: $selectedModel) {
                    ForEach(models, id: \.0) { model in
                        Text(model.1).tag(model.0)
                    }
                }
            } header: {
                Text("Anthropic Claude")
            } footer: {
                Text("Get your API key from console.anthropic.com")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadAPIKey()
        }
    }
    
    private func loadAPIKey() {
        if let storedKey = KeychainManager.loadString(.anthropicAPIKey) {
            apiKey = storedKey
            hasKey = true
        }
    }
    
    private func saveAPIKey(_ key: String) {
        guard !key.isEmpty else {
            hasKey = false
            return
        }
        let success = KeychainManager.save(key, for: .anthropicAPIKey)
        hasKey = success
    }
}

struct AudioSettingsView: View {
    @Binding var audioSource: String
    
    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Audio Source"), selection: $audioSource) {
                    Text("System Audio (Meeting apps)").tag("system")
                    Text("Microphone").tag("microphone")
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Capture Source")
            } footer: {
                if audioSource == "system" {
                    Text("Captures audio from Zoom, Meet, Teams and other apps. Requires Screen Recording permission. Note: App restart required after first permission grant.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Captures audio from your microphone. Useful when meeting audio plays through speakers.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct PrivacySettingsView: View {
    @Binding var analyticsEnabled: Bool
    
    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Send anonymous usage analytics"), isOn: $analyticsEnabled)
            } header: {
                Text("Analytics")
            } footer: {
                Text("Help improve Notch Assistant by sharing anonymous usage data. No meeting content is ever collected.")
                    .foregroundStyle(.secondary)
            }
            
            Section {
                LabeledContent(String(localized: "Transcripts")) {
                    Text("Memory only (never stored)")
                        .foregroundStyle(.secondary)
                }
                
                LabeledContent(String(localized: "API Key")) {
                    Text("Stored in Keychain")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Data Storage")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
