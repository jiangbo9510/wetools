import CoreGraphics
import Foundation

enum OCRLanguagePreference: String, CaseIterable, Codable, Identifiable {
    case automatic
    case chinese
    case english
    case chineseEnglish

    var id: String { rawValue }

    var recognitionLanguages: [String] {
        switch self {
        case .automatic:
            return ["zh-Hans", "en-US"]
        case .chinese:
            return ["zh-Hans"]
        case .english:
            return ["en-US"]
        case .chineseEnglish:
            return ["zh-Hans", "en-US"]
        }
    }
}

struct OCRResult: Codable, Equatable {
    var fullText: String
    var observations: [OCRObservation]
    var languageHints: [String]
    var createdAt: Date
}

struct OCRObservation: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var confidence: Float
    var boundingBox: CGRect
    var language: String?
    var lines: [String]
}
