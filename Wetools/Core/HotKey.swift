import Carbon
import Foundation

struct HotKey: Codable, Equatable, Hashable {
    var key: HotKeyKey
    var modifiers: HotKeyModifiers
}

struct HotKeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt32

    static let command = HotKeyModifiers(rawValue: UInt32(cmdKey))
    static let option = HotKeyModifiers(rawValue: UInt32(optionKey))
    static let control = HotKeyModifiers(rawValue: UInt32(controlKey))
    static let shift = HotKeyModifiers(rawValue: UInt32(shiftKey))

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UInt32.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayText: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}

struct HotKeyKey: Codable, Equatable, Hashable, Identifiable {
    var keyCode: UInt32
    var displayText: String

    var id: UInt32 { keyCode }

    init(keyCode: UInt32, displayText: String) {
        self.keyCode = keyCode
        self.displayText = displayText
    }
}

extension HotKeyKey {
    static let five = HotKeyKey(keyCode: UInt32(kVK_ANSI_5), displayText: "5")
    static let six = HotKeyKey(keyCode: UInt32(kVK_ANSI_6), displayText: "6")
    static let v = HotKeyKey(keyCode: UInt32(kVK_ANSI_V), displayText: "V")
}

extension HotKey {
    var displayText: String {
        "\(modifiers.displayText)\(key.displayText)"
    }
}
