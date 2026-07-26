import Foundation

final class JSONFileStore<Value: Codable> {
    private let fileName: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileName: String) {
        self.fileName = fileName
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func load() -> Value? {
        do {
            let url = try fileURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try decoder.decode(Value.self, from: data)
        } catch {
            NSLog("Failed to load \(fileName): \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ value: Value) {
        do {
            let url = try fileURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("Failed to save \(fileName): \(error.localizedDescription)")
        }
    }

    private func fileURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL.appendingPathComponent("Wetools", isDirectory: true).appendingPathComponent(fileName)
    }
}
