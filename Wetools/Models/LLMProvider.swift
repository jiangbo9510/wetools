import Foundation

enum LLMProviderType: String, CaseIterable, Codable, Identifiable {
    case openAICompatible
    case ollama
    case customHTTP

    var id: String { rawValue }
}

struct LLMProvider: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var providerType: LLMProviderType
    var baseURL: String
    var apiKeySecretRef: String?
    var model: String
    var visionModel: String?
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    static func empty() -> LLMProvider {
        let now = Date()
        return LLMProvider(
            id: UUID(),
            name: "",
            providerType: .openAICompatible,
            baseURL: "https://api.openai.com",
            apiKeySecretRef: nil,
            model: "",
            visionModel: nil,
            enabled: false,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct LLMProviderSnapshot: Codable {
    var providers: [LLMProvider]
}
