import Foundation

@MainActor
final class LLMProviderStore: ObservableObject {
    @Published private(set) var providers: [LLMProvider] = []
    @Published var lastErrorMessage: String?

    private let store: JSONFileStore<LLMProviderSnapshot>
    private let keychainService: KeychainService

    init(
        store: JSONFileStore<LLMProviderSnapshot> = JSONFileStore(fileName: "llm-providers.json"),
        keychainService: KeychainService = KeychainService()
    ) {
        self.store = store
        self.keychainService = keychainService
        providers = loadProviders()
    }

    func loadProviders() -> [LLMProvider] {
        store.load()?.providers ?? []
    }

    func saveProviders() {
        store.save(LLMProviderSnapshot(providers: providers))
    }

    func addProvider(_ provider: LLMProvider, apiKey: String?) {
        var newProvider = provider
        let now = Date()
        newProvider.createdAt = now
        newProvider.updatedAt = now
        persistSecretIfNeeded(for: &newProvider, apiKey: apiKey)
        providers.append(newProvider)
        normalizeEnabledProvider(activeID: newProvider.enabled ? newProvider.id : nil)
        saveProviders()
    }

    func updateProvider(_ provider: LLMProvider, apiKey: String?) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        var updated = provider
        updated.updatedAt = Date()
        persistSecretIfNeeded(for: &updated, apiKey: apiKey)
        providers[index] = updated
        normalizeEnabledProvider(activeID: updated.enabled ? updated.id : nil)
        saveProviders()
    }

    func deleteProvider(_ provider: LLMProvider) {
        if let ref = provider.apiKeySecretRef {
            do {
                try keychainService.deleteSecret(account: ref)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
        providers.removeAll { $0.id == provider.id }
        saveProviders()
    }

    func setEnabledProvider(_ provider: LLMProvider) {
        normalizeEnabledProvider(activeID: provider.id)
        saveProviders()
    }

    func getActiveProvider() -> LLMProvider? {
        providers.first(where: \.enabled)
    }

    func readAPIKey(for provider: LLMProvider) -> String? {
        guard let ref = provider.apiKeySecretRef else { return nil }
        return try? keychainService.readSecret(account: ref)
    }

    func testConnection(for provider: LLMProvider) async -> Result<Bool, Error> {
        do {
            let apiKey = readAPIKey(for: provider)
            let client = LLMClientFactory.makeClient(provider: provider, apiKey: apiKey)
            let isConnected = try await client.testConnection()
            return .success(isConnected)
        } catch {
            return .failure(error)
        }
    }

    private func persistSecretIfNeeded(for provider: inout LLMProvider, apiKey: String?) {
        guard let apiKey, !apiKey.isEmpty else { return }
        let ref = provider.apiKeySecretRef ?? "llm-provider-\(provider.id.uuidString)"

        do {
            try keychainService.updateSecret(apiKey, account: ref)
            provider.apiKeySecretRef = ref
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func normalizeEnabledProvider(activeID: UUID?) {
        guard let activeID else { return }
        providers = providers.map { provider in
            var copy = provider
            copy.enabled = provider.id == activeID
            copy.updatedAt = copy.enabled ? Date() : copy.updatedAt
            return copy
        }
    }
}
