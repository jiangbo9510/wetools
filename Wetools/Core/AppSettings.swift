import AppKit
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    struct Snapshot: Codable {
        var screenshotHotKey: HotKey
        var clipboardHistoryHotKey: HotKey
        var maxClipboardHistory: Int
        var launchAtLogin: Bool
        var autoPaste: Bool
        var defaultSaveDirectory: String
        var appLanguage: AppLanguage
        var ocrLanguagePreference: OCRLanguagePreference
        var recordingSystemAudio: Bool

        init(
            screenshotHotKey: HotKey,
            clipboardHistoryHotKey: HotKey,
            maxClipboardHistory: Int,
            launchAtLogin: Bool,
            autoPaste: Bool,
            defaultSaveDirectory: String,
            appLanguage: AppLanguage,
            ocrLanguagePreference: OCRLanguagePreference,
            recordingSystemAudio: Bool
        ) {
            self.screenshotHotKey = screenshotHotKey
            self.clipboardHistoryHotKey = clipboardHistoryHotKey
            self.maxClipboardHistory = maxClipboardHistory
            self.launchAtLogin = launchAtLogin
            self.autoPaste = autoPaste
            self.defaultSaveDirectory = defaultSaveDirectory
            self.appLanguage = appLanguage
            self.ocrLanguagePreference = ocrLanguagePreference
            self.recordingSystemAudio = recordingSystemAudio
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            screenshotHotKey = try container.decode(HotKey.self, forKey: .screenshotHotKey)
            clipboardHistoryHotKey = try container.decode(HotKey.self, forKey: .clipboardHistoryHotKey)
            maxClipboardHistory = try container.decode(Int.self, forKey: .maxClipboardHistory)
            launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
            autoPaste = try container.decode(Bool.self, forKey: .autoPaste)
            defaultSaveDirectory = try container.decode(String.self, forKey: .defaultSaveDirectory)
            appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .system
            ocrLanguagePreference = try container.decodeIfPresent(OCRLanguagePreference.self, forKey: .ocrLanguagePreference) ?? .automatic
            recordingSystemAudio = try container.decodeIfPresent(
                Bool.self,
                forKey: .recordingSystemAudio
            ) ?? false
        }
    }

    @Published var screenshotHotKey: HotKey {
        didSet { persistChange() }
    }

    @Published var clipboardHistoryHotKey: HotKey {
        didSet { persistChange() }
    }

    @Published var maxClipboardHistory: Int {
        didSet { persistChange() }
    }

    @Published var launchAtLogin: Bool {
        didSet { persistChange() }
    }

    @Published var autoPaste: Bool {
        didSet { persistChange() }
    }

    @Published var defaultSaveDirectory: String {
        didSet { persistChange() }
    }

    @Published var appLanguage: AppLanguage {
        didSet { persistChange() }
    }

    @Published var ocrLanguagePreference: OCRLanguagePreference {
        didSet { persistChange() }
    }

    @Published var recordingSystemAudio: Bool {
        didSet { persistChange() }
    }

    var onChange: (() -> Void)?

    private let store: JSONFileStore<Snapshot>
    private var isLoading = false

    init(store: JSONFileStore<Snapshot>) {
        self.store = store
        let snapshot = store.load() ?? Self.defaultSnapshot()
        isLoading = true
        screenshotHotKey = snapshot.screenshotHotKey
        clipboardHistoryHotKey = snapshot.clipboardHistoryHotKey
        maxClipboardHistory = snapshot.maxClipboardHistory
        launchAtLogin = snapshot.launchAtLogin
        autoPaste = snapshot.autoPaste
        defaultSaveDirectory = snapshot.defaultSaveDirectory
        appLanguage = snapshot.appLanguage.resolved
        ocrLanguagePreference = snapshot.ocrLanguagePreference
        recordingSystemAudio = snapshot.recordingSystemAudio
        isLoading = false
        if snapshot.appLanguage == .system {
            store.save(self.snapshot())
        }
    }

    func chooseDefaultSaveDirectory(prompt: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt

        if panel.runModal() == .OK, let url = panel.url {
            defaultSaveDirectory = url.path
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            screenshotHotKey: screenshotHotKey,
            clipboardHistoryHotKey: clipboardHistoryHotKey,
            maxClipboardHistory: maxClipboardHistory,
            launchAtLogin: launchAtLogin,
            autoPaste: autoPaste,
            defaultSaveDirectory: defaultSaveDirectory,
            appLanguage: appLanguage,
            ocrLanguagePreference: ocrLanguagePreference,
            recordingSystemAudio: recordingSystemAudio
        )
    }

    private func persistChange() {
        guard !isLoading else { return }
        store.save(snapshot())
        onChange?()
    }

    private static func defaultSnapshot() -> Snapshot {
        Snapshot(
            screenshotHotKey: HotKey(key: .five, modifiers: [.command, .shift]),
            clipboardHistoryHotKey: HotKey(key: .v, modifiers: [.command, .shift]),
            maxClipboardHistory: 50,
            launchAtLogin: false,
            autoPaste: false,
            defaultSaveDirectory: FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory(),
            appLanguage: .systemDefault,
            ocrLanguagePreference: .automatic,
            recordingSystemAudio: false
        )
    }
}
