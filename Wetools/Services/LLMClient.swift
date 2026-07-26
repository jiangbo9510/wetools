import AppKit
import Foundation

enum LLMClientError: LocalizedError {
    case missingProvider
    case missingAPIKey
    case invalidBaseURL
    case unsupportedProvider
    case networkFailed(String)
    case modelNotFound
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingProvider:
            return "No active provider is configured."
        case .missingAPIKey:
            return "API key is missing."
        case .invalidBaseURL:
            return "Base URL is invalid."
        case .unsupportedProvider:
            return "Provider type is not supported by this client."
        case .networkFailed(let message):
            return "Network request failed: \(message)"
        case .modelNotFound:
            return "Model was not found."
        case .invalidResponse:
            return "The service returned an unexpected response."
        case .serverError(let statusCode, let message):
            return "Service returned HTTP \(statusCode): \(message)"
        }
    }
}

protocol LLMClient {
    func chat(prompt: String, text: String) async throws -> String
    func visionAnalyze(image: NSImage, prompt: String) async throws -> String
    func testConnection() async throws -> Bool
}

enum LLMClientFactory {
    static func makeClient(provider: LLMProvider, apiKey: String?) -> LLMClient {
        switch provider.providerType {
        case .openAICompatible:
            return OpenAICompatibleLLMClient(provider: provider, apiKey: apiKey)
        case .ollama:
            return OllamaLLMClient(provider: provider)
        case .customHTTP:
            return CustomHTTPLLMClient(provider: provider)
        }
    }
}

final class OpenAICompatibleLLMClient: LLMClient {
    private let provider: LLMProvider
    private let apiKey: String?
    private let session: URLSession

    init(provider: LLMProvider, apiKey: String?, timeout: TimeInterval = 20) {
        self.provider = provider
        self.apiKey = apiKey
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
    }

    func chat(prompt: String, text: String) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw LLMClientError.missingAPIKey }
        guard !provider.model.isEmpty else { throw LLMClientError.modelNotFound }
        let url = try endpoint(path: "/v1/chat/completions")

        let payload = ChatCompletionRequest(
            model: provider.model,
            messages: [
                ChatMessage(role: "system", content: prompt),
                ChatMessage(role: "user", content: text)
            ],
            temperature: 0.2
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let response: ChatCompletionResponse = try await send(request)
        guard let content = response.choices.first?.message.content else {
            throw LLMClientError.invalidResponse
        }
        return content
    }

    func visionAnalyze(image: NSImage, prompt: String) async throws -> String {
        throw LLMClientError.unsupportedProvider
    }

    func testConnection() async throws -> Bool {
        guard let apiKey, !apiKey.isEmpty else { throw LLMClientError.missingAPIKey }
        var request = URLRequest(url: try endpoint(path: "/v1/models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let _: ModelsResponse = try await send(request)
        return true
    }

    private func endpoint(path: String) throws -> URL {
        guard let baseURL = URL(string: provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LLMClientError.invalidBaseURL
        }
        return baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMClientError.invalidResponse
            }

            if httpResponse.statusCode == 404 {
                throw LLMClientError.modelNotFound
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? ""
                throw LLMClientError.serverError(httpResponse.statusCode, message)
            }

            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as LLMClientError {
            throw error
        } catch {
            throw LLMClientError.networkFailed(error.localizedDescription)
        }
    }
}

final class OllamaLLMClient: LLMClient {
    private let provider: LLMProvider
    private let session: URLSession

    init(provider: LLMProvider, timeout: TimeInterval = 10) {
        self.provider = provider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
    }

    func chat(prompt: String, text: String) async throws -> String {
        throw LLMClientError.unsupportedProvider
    }

    func visionAnalyze(image: NSImage, prompt: String) async throws -> String {
        throw LLMClientError.unsupportedProvider
    }

    func testConnection() async throws -> Bool {
        guard let baseURL = URL(string: provider.baseURL) else { throw LLMClientError.invalidBaseURL }
        let url = baseURL.appendingPathComponent("api/tags")
        let (_, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else { throw LLMClientError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LLMClientError.serverError(httpResponse.statusCode, "")
        }
        return true
    }
}

final class CustomHTTPLLMClient: LLMClient {
    private let provider: LLMProvider
    private let session: URLSession

    init(provider: LLMProvider, timeout: TimeInterval = 10) {
        self.provider = provider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
    }

    func chat(prompt: String, text: String) async throws -> String {
        throw LLMClientError.unsupportedProvider
    }

    func visionAnalyze(image: NSImage, prompt: String) async throws -> String {
        throw LLMClientError.unsupportedProvider
    }

    func testConnection() async throws -> Bool {
        guard let url = URL(string: provider.baseURL) else { throw LLMClientError.invalidBaseURL }
        let (_, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else { throw LLMClientError.invalidResponse }
        guard (200...399).contains(httpResponse.statusCode) else {
            throw LLMClientError.serverError(httpResponse.statusCode, "")
        }
        return true
    }
}

private struct ChatCompletionRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        var message: ChatMessage
    }

    var choices: [Choice]
}

private struct ModelsResponse: Decodable {
    var data: [ModelItem]?
}

private struct ModelItem: Decodable {
    var id: String?
}
