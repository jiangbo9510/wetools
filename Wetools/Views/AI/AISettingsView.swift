import SwiftUI

struct AISettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var localization: LocalizationManager
    @ObservedObject var providerStore: LLMProviderStore

    @State private var draftProvider = LLMProvider.empty()
    @State private var draftAPIKey = ""
    @State private var selectedProviderID: UUID?
    @State private var connectionStatus = ""
    @State private var isTestingConnection = false

    var body: some View {
        HStack(spacing: 18) {
            providerList
                .frame(width: 260)

            Divider()

            providerEditor
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            selectFirstProviderIfNeeded()
        }
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.string("ai.providers"))
                .font(.headline)

            List(providerStore.providers, selection: $selectedProviderID) { provider in
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.name.isEmpty ? localization.string("ai.untitledProvider") : provider.name)
                        .font(.body)
                    Text(provider.providerType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if provider.enabled {
                        Text(localization.string("ai.enabled"))
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                .tag(provider.id)
            }
            .onChange(of: selectedProviderID) { _ in
                loadSelectedProvider()
            }

            HStack {
                Button(localization.string("common.add")) {
                    draftProvider = LLMProvider.empty()
                    draftAPIKey = ""
                    selectedProviderID = nil
                    connectionStatus = ""
                }

                Button(localization.string("common.delete")) {
                    guard let provider = selectedProvider else { return }
                    providerStore.deleteProvider(provider)
                    selectedProviderID = nil
                    draftProvider = LLMProvider.empty()
                    draftAPIKey = ""
                }
                .disabled(selectedProvider == nil)
            }
        }
    }

    private var providerEditor: some View {
        Form {
            Section(localization.string("ai.providerDetails")) {
                TextField(localization.string("ai.providerName"), text: $draftProvider.name)

                Picker(localization.string("ai.providerType"), selection: $draftProvider.providerType) {
                    ForEach(LLMProviderType.allCases) { type in
                        Text(localization.string("ai.providerType.\(type.rawValue)")).tag(type)
                    }
                }

                TextField(localization.string("ai.baseURL"), text: $draftProvider.baseURL)
                TextField(localization.string("ai.model"), text: $draftProvider.model)
                TextField(localization.string("ai.visionModel"), text: Binding(
                    get: { draftProvider.visionModel ?? "" },
                    set: { draftProvider.visionModel = $0.isEmpty ? nil : $0 }
                ))
                SecureField(localization.string("ai.apiKey"), text: $draftAPIKey)

                Toggle(localization.string("ai.setEnabled"), isOn: $draftProvider.enabled)
            }

            Section(localization.string("ocr.settings")) {
                Picker(localization.string("ocr.languagePreference"), selection: $settings.ocrLanguagePreference) {
                    ForEach(OCRLanguagePreference.allCases) { preference in
                        Text(localization.string("ocr.preference.\(preference.rawValue)")).tag(preference)
                    }
                }
            }

            HStack {
                Button(localization.string("common.save")) {
                    saveProvider()
                }

                Button(localization.string("ai.testConnection")) {
                    testConnection()
                }
                .disabled(isTestingConnection)

                if isTestingConnection {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(connectionStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var selectedProvider: LLMProvider? {
        guard let selectedProviderID else { return nil }
        return providerStore.providers.first { $0.id == selectedProviderID }
    }

    private func selectFirstProviderIfNeeded() {
        guard selectedProviderID == nil, let first = providerStore.providers.first else { return }
        selectedProviderID = first.id
        loadSelectedProvider()
    }

    private func loadSelectedProvider() {
        guard let provider = selectedProvider else { return }
        draftProvider = provider
        draftAPIKey = ""
        connectionStatus = ""
    }

    private func saveProvider() {
        if selectedProvider == nil {
            providerStore.addProvider(draftProvider, apiKey: draftAPIKey)
            selectedProviderID = draftProvider.id
        } else {
            providerStore.updateProvider(draftProvider, apiKey: draftAPIKey)
        }
        connectionStatus = localization.string("ai.saved")
    }

    private func testConnection() {
        let provider = draftProvider
        isTestingConnection = true
        connectionStatus = localization.string("ai.testing")

        Task {
            let result = await providerStore.testConnection(for: provider)
            await MainActor.run {
                isTestingConnection = false
                switch result {
                case .success:
                    connectionStatus = localization.string("ai.testSucceeded")
                case .failure(let error):
                    connectionStatus = localization.string("ai.testFailed", error.localizedDescription)
                }
            }
        }
    }
}
