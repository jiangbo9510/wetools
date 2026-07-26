import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var localization: LocalizationManager

    var body: some View {
        TabView {
            generalView
                .tabItem {
                    Label(localization.string("settings.tab.general"), systemImage: "gearshape")
                }

            shortcutsView
                .tabItem {
                    Label(localization.string("settings.tab.shortcuts"), systemImage: "keyboard")
                }

            permissionsView
                .tabItem {
                    Label(localization.string("settings.tab.permissions"), systemImage: "lock.shield")
                }

            ocrView
                .tabItem {
                    Label(localization.string("settings.tab.ocr"), systemImage: "text.viewfinder")
                }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 620)
        .onAppear {
            localization.language = settings.appLanguage
        }
        .onChange(of: settings.appLanguage) { newValue in
            localization.language = newValue
        }
    }

    private var generalView: some View {
        Form {
            Section {
                Picker(selection: $settings.appLanguage) {
                    ForEach(AppLanguage.selectableCases) { language in
                        Text(localization.displayName(for: language)).tag(language)
                    }
                } label: {
                    Image(systemName: "globe")
                        .accessibilityLabel(localization.string("settings.language"))
                }
            }

            Section(localization.string("settings.section.clipboard")) {
                Stepper(value: $settings.maxClipboardHistory, in: 10...500, step: 10) {
                    Text(localization.string("settings.maxClipboardHistory", settings.maxClipboardHistory))
                }

                Toggle(localization.string("settings.autoPaste"), isOn: $settings.autoPaste)
            }

            Section(localization.string("settings.section.launch")) {
                Toggle(localization.string("settings.launchAtLogin"), isOn: $settings.launchAtLogin)
                    .disabled(true)
                Text(localization.string("settings.launchAtLogin.phase6"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(localization.string("settings.section.saveLocation")) {
                HStack {
                    Text(settings.defaultSaveDirectory)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(localization.string("common.choose")) {
                        settings.chooseDefaultSaveDirectory(prompt: localization.string("common.choose"))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsView: some View {
        Form {
            Section(localization.string("settings.section.globalHotKeys")) {
                HotKeyRecorderView(title: localization.string("action.screenshotTool"), hotKey: $settings.screenshotHotKey, localization: localization)
                HotKeyRecorderView(title: localization.string("action.clipboardHistory"), hotKey: $settings.clipboardHistoryHotKey, localization: localization)
            }

            Text(localization.string("settings.hotkeys.note"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var permissionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            PermissionStatusView(
                title: localization.string("permission.screenRecording"),
                isGranted: permissionManager.hasScreenRecordingPermission,
                grantedText: localization.string("permission.granted"),
                requiredText: localization.string("permission.required"),
                actionTitle: localization.string("permission.openSettings"),
                action: permissionManager.requestScreenRecordingPermission
            )

            PermissionStatusView(
                title: localization.string("permission.accessibility"),
                isGranted: permissionManager.hasAccessibilityPermission,
                grantedText: localization.string("permission.granted"),
                requiredText: localization.string("permission.required"),
                actionTitle: localization.string("permission.openSettings"),
                action: permissionManager.requestAccessibilityPermission
            )

            PermissionStatusView(
                title: localization.string("permission.microphone"),
                isGranted: permissionManager.hasMicrophonePermission,
                grantedText: localization.string("permission.granted"),
                requiredText: localization.string("permission.optionalRecording"),
                actionTitle: localization.string("permission.openSettings"),
                action: permissionManager.requestMicrophonePermission
            )

            Button(localization.string("permission.refresh"), action: permissionManager.refresh)

            Spacer()
        }
        .padding(.top, 12)
    }

    private var ocrView: some View {
        Form {
            Section(localization.string("ocr.settings")) {
                Picker(localization.string("ocr.languagePreference"), selection: $settings.ocrLanguagePreference) {
                    ForEach(OCRLanguagePreference.allCases) { preference in
                        Text(localization.string("ocr.preference.\(preference.rawValue)")).tag(preference)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
