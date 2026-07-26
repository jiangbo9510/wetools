import AppKit
import Vision

enum OCRManagerError: LocalizedError {
    case invalidImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Image cannot be converted for OCR."
        case .recognitionFailed:
            return "Text recognition failed."
        }
    }
}

@MainActor
final class OCRManager {
    func recognizeText(image: NSImage, languages: [String]) async throws -> OCRResult {
        guard let cgImage = image.cgImageForOCR else {
            throw OCRManagerError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    guard let observations = request.results else {
                        continuation.resume(throwing: OCRManagerError.recognitionFailed)
                        return
                    }

                    let mapped = observations.compactMap { observation -> OCRObservation? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        let text = candidate.string
                        return OCRObservation(
                            text: text,
                            confidence: candidate.confidence,
                            boundingBox: observation.boundingBox,
                            language: nil,
                            lines: text.components(separatedBy: .newlines)
                        )
                    }

                    continuation.resume(returning: OCRResult(
                        fullText: mapped.map(\.text).joined(separator: "\n"),
                        observations: mapped,
                        languageHints: languages,
                        createdAt: Date()
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension NSImage {
    var cgImageForOCR: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
