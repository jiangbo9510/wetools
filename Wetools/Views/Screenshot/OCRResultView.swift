import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OCRResultView: View {
    let result: OCRResult
    let image: NSImage
    @ObservedObject var localization: LocalizationManager
    @ObservedObject var providerStore: LLMProviderStore

    @State private var selectedAction = LLMTextAction.summarize
    @State private var customPrompt = ""
    @State private var llmResponse = ""
    @State private var errorMessage: String?
    @State private var isSending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localization.string("ocr.result"))
                .font(.headline)

            TextEditor(text: .constant(result.fullText))
                .font(.body)
                .frame(minHeight: 120)

            HStack {
                Button(localization.string("ocr.copyAll"), action: copyAll)
                Button(localization.string("ocr.saveText"), action: saveText)
            }

            Divider()

            HStack {
                Picker(localization.string("llm.action"), selection: $selectedAction) {
                    ForEach(LLMTextAction.allCases) { action in
                        Text(localization.string(action.localizationKey)).tag(action)
                    }
                }
                .frame(minWidth: 220)

                TextField(localization.string("llm.customPrompt"), text: $customPrompt)
                    .disabled(selectedAction != .custom)

                Button(localization.string("llm.send")) {
                    sendToLLM()
                }
                .disabled(isSending)

                if isSending {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !llmResponse.isEmpty {
                TextEditor(text: $llmResponse)
                    .frame(minHeight: 100)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.fullText, forType: .string)
    }

    private func saveText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = localization.string("ocr.defaultFileName")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try result.fullText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendToLLM() {
        guard let provider = providerStore.getActiveProvider() else {
            errorMessage = localization.string("llm.error.noProvider")
            return
        }

        let apiKey = providerStore.readAPIKey(for: provider)
        let client = LLMClientFactory.makeClient(provider: provider, apiKey: apiKey)
        let prompt = selectedAction.prompt(localization: localization, customPrompt: customPrompt)

        isSending = true
        errorMessage = nil

        Task {
            do {
                let response = try await client.chat(prompt: prompt, text: result.fullText)
                await MainActor.run {
                    llmResponse = response
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }
}

enum LLMTextAction: String, CaseIterable, Identifiable {
    case summarize
    case translateToChinese
    case translateToEnglish
    case extractKeyPoints
    case custom

    var id: String { rawValue }

    var localizationKey: String {
        "llm.action.\(rawValue)"
    }

    @MainActor
    func prompt(localization: LocalizationManager, customPrompt: String) -> String {
        switch self {
        case .summarize:
            return localization.string("llm.prompt.summarize")
        case .translateToChinese:
            return localization.string("llm.prompt.translateToChinese")
        case .translateToEnglish:
            return localization.string("llm.prompt.translateToEnglish")
        case .extractKeyPoints:
            return localization.string("llm.prompt.extractKeyPoints")
        case .custom:
            return customPrompt
        }
    }
}
