import SwiftUI

struct SettingsView: View {
    @AppStorage("apiKey") private var apiKey: String = ""
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("analyticsEnabled") private var analyticsEnabled: Bool = true
    @AppStorage("selectedModel") private var selectedModel: String = "claude-3-haiku-20240307"
    
    var body: some View {
        TabView {
            GeneralSettingsView(launchAtLogin: $launchAtLogin)
                .tabItem {
                    Label(String(localized: "General"), systemImage: "gear")
                }
            
            APISettingsView(apiKey: $apiKey, selectedModel: $selectedModel)
                .tabItem {
                    Label(String(localized: "API"), systemImage: "key")
                }
            
            PrivacySettingsView(analyticsEnabled: $analyticsEnabled)
                .tabItem {
                    Label(String(localized: "Privacy"), systemImage: "hand.raised")
                }
        }
        .frame(width: 480, height: 320)
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
    @Binding var apiKey: String
    @Binding var selectedModel: String
    @State private var showingKey = false
    
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
                    } else {
                        SecureField(String(localized: "API Key"), text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: { showingKey.toggle() }) {
                        Image(systemName: showingKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
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
