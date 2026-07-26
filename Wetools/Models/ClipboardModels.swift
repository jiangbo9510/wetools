import Foundation

enum ClipboardItemKind: String, Codable {
    case text
    case image
    case file
}

struct ClipboardItem: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: ClipboardItemKind
    var preview: String
    var text: String?
    var imagePath: String?
    var filePath: String?
    var fileType: String?
    var contentHash: String
    var createdAt: Date
}

struct ClipboardHistorySnapshot: Codable {
    var items: [ClipboardItem]
}
