import Foundation

@MainActor
final class LocalizationManager: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "app.language"

    init(initialLanguage: AppLanguage? = nil) {
        language = (initialLanguage ?? Self.savedLanguage()).resolved
    }

    func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizedString(forKey: key)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }

    func displayName(for language: AppLanguage) -> String {
        switch language {
        case .system:
            return string("language.system")
        case .simplifiedChinese:
            return string("language.zhHans")
        case .english:
            return string("language.english")
        }
    }

    private func localizedString(forKey key: String) -> String {
        guard let bundle = localizedBundle else {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private var localizedBundle: Bundle? {
        let identifier = language.localeIdentifier ?? Locale.preferredLanguages.first ?? "en"
        let normalized = identifier.hasPrefix("zh") ? "zh-Hans" : "en"
        guard let path = Bundle.main.path(forResource: normalized, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    private var locale: Locale {
        Locale(identifier: language.localeIdentifier ?? Locale.preferredLanguages.first ?? "en")
    }

    private static func savedLanguage() -> AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .systemDefault
        }
        return language.resolved
    }
}
