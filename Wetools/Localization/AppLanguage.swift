import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }

    static let selectableCases: [AppLanguage] = [.simplifiedChinese, .english]

    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    var resolved: AppLanguage {
        self == .system ? Self.systemDefault : self
    }

    var localeIdentifier: String? {
        switch resolved {
        case .system:
            return nil
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }
}
