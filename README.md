# Wetools

Wetools is a native macOS productivity app planned as a menu bar tool that combines screenshot, screen recording, and clipboard history workflows.

## Overall Technical Plan

- Build a native macOS app with Swift, SwiftUI, and AppKit.
- Keep the app resident in the menu bar with `NSStatusItem`.
- Use AppKit where system integration is required: status menu, windows, pasteboard, permissions, and global shortcuts.
- Use SwiftUI for app-facing panels such as Settings, Clipboard History, and Preview.
- Use dedicated manager types for system workflows:
  - `HotKeyManager` for global shortcuts.
  - `ClipboardManager` for pasteboard monitoring.
  - `ScreenshotManager` for screenshot flows.
  - `ScreenRecordingManager` for ScreenCaptureKit recording.
  - `PermissionManager` for permission detection and guidance.
- Use `AppSettings` as the single observable source for user preferences.
- Use a Store layer for local JSON and file persistence.
- Store all user data locally under Application Support. No network upload is planned.

## macOS Permissions

- Screen Recording: required for ScreenCaptureKit screenshots and recording on macOS 12.3+.
- Accessibility: required for optional auto-paste, simulated keyboard input, and scrolling screenshot automation.
- File Save Access: standard `NSSavePanel` or security-scoped bookmarks may be needed if users choose locations outside normal app containers.
- Launch at Login: handled later through ServiceManagement.

## Scrolling Screenshot Plan

The long screenshot path targets macOS 13+ on Apple Silicon and is split into independent services:

- `ScrollabilityProbeService`: retained for the standalone developer diagnostic tool; the app no longer blocks long screenshots with a support probe.
- `ScrollDriver`: listens for manual scrolling inside the selected region, waits for each gesture and rendering to settle, and captures up to 60 physical-pixel frames.
- `ImageStitcher`: validates every adjacent frame, detects fixed headers, footers, and side columns with multi-frame median statistics, registers only the scrolling body, and hard-cuts at the lowest-error seam.
- `FidelityFrameComposer`: renders fixed textured regions from the first frame once and composes the registered scrolling body. Ambiguous boundaries fail instead of falling back to full-frame tiling or cropping.
- `RepeatedContentSelfCheck`: rejects periodic vertical repetition before any image is written or copied.
- The live preview and final PNG use the same stitch result. PNG point size is retained so Retina captures are exported with 144 DPI metadata.

Dynamic video/canvas content and applications that cannot produce stable, overlapping frames fail during registration. Failure discards all captured frames and leaves files and the clipboard unchanged.

Clicking Start immediately captures the first frame and opens the live preview. The app does not inject a test scroll or require Accessibility permission before capture; column splitting begins after the user manually scrolls.

Manual scrolling supports either upward or downward capture, but one capture must keep a single direction. If adjacent frames no longer have validated overlap, capture fails immediately as scrolling too fast instead of estimating the missing content.

`ScrollingCaptureConfig.strictness` defaults to `balanced`. Balanced mode accepts
registration when the peak ratio, injected-scroll estimate, or previous-frame
velocity is trustworthy, tolerates one inertial reverse frame, and checks periodic
repetition only in detected fixed columns. `strict` retains the original regression
thresholds.

To enable debug seam output, set `ScrollingCaptureConfig.debugSeams` to `true`. Each frame pair also logs its measured `dy`, confidence, and whether the measured scroll estimate was used. Failed captures save diagnostic frames and registration logs under `/tmp`; repeated-content failures also save an autocorrelation heatmap.

Run `swift run ScrollProbeTest ... --debug-detect` to save F0/F1, block metrics, and a texture/MAE diagnostic overlay under `/tmp`.
The diagnostic output also includes `column_diff.csv`, split boundaries, and the detected layout type.

## Project Directory

```text
wetools/
├── AGENTS.md
├── README.md
├── Wetools.xcodeproj/
│   └── project.pbxproj
└── Wetools/
    ├── App/
    │   ├── AppDelegate.swift
    │   └── WetoolsApp.swift
    ├── Core/
    │   ├── AppSettings.swift
    │   └── HotKey.swift
    ├── Managers/
    │   ├── HotKeyManager.swift
    │   └── PermissionManager.swift
    ├── Resources/
    │   ├── Info.plist
    │   └── Wetools.entitlements
    ├── Stores/
    │   └── JSONFileStore.swift
    └── Views/
        ├── PermissionStatusView.swift
        └── SettingsView.swift
```

## Module Responsibilities

- App: application lifecycle, menu bar status item, window orchestration.
- Core: observable app state and shared value types.
- Localization: app language selection and runtime localized string lookup.
- Models: OCR and other domain data models.
- Managers: macOS integration and side-effect-heavy system workflows.
- Services: macOS-native OCR, translation, and system integration services.
- Stores: JSON and file persistence only.
- Views: SwiftUI presentation with no business or storage logic.

## Extended Architecture

```text
Wetools/
├── App/
│   ├── AppDelegate.swift
│   └── WetoolsApp.swift
├── Core/
│   ├── AppSettings.swift
│   └── HotKey.swift
├── Localization/
│   ├── AppLanguage.swift
│   └── LocalizationManager.swift
├── Managers/
│   ├── HotKeyManager.swift
│   └── PermissionManager.swift
├── Models/
│   └── OCRModels.swift
├── Services/
│   └── OCRManager.swift
├── Stores/
│   └── JSONFileStore.swift
├── Views/
│   ├── Screenshot/
│   │   ├── OCRResultView.swift
│   │   └── ScreenshotPreviewView.swift
│   ├── PermissionStatusView.swift
│   └── SettingsView.swift
└── Resources/
    ├── en.lproj/Localizable.strings
    ├── zh-Hans.lproj/Localizable.strings
    ├── Info.plist
    └── Wetools.entitlements
```

## Internationalization

- `AppLanguage` supports system, Simplified Chinese, and English.
- `LocalizationManager` loads `Localizable.strings` from `zh-Hans.lproj` or `en.lproj`.
- SwiftUI views observe `LocalizationManager`, so switching language in Settings refreshes visible strings.
- All new visible UI strings use localization keys.

Example:

```swift
Text(localization.string("settings.title"))
Button(localization.string("common.save")) { saveSettings() }
```

## OCR and Translation

- Text recognition uses the macOS Apple Vision framework and runs locally.
- Translation uses the translation capability built into macOS.
- These features do not require third-party services or credentials.
- Screenshot content is not uploaded by OCR or translation.

## Implementation Phases

1. Phase 1: menu bar app, settings page, global shortcuts.
2. Phase 2: clipboard history monitoring, storage, and floating history panel.
3. Phase 3: basic screenshot capture and preview.
4. Phase 4: screen recording with ScreenCaptureKit and AVFoundation.
5. Phase 5: scrolling screenshot MVP.
6. Phase 6: permission guidance polish, optimization, and packaging.

## Phase 1

Added files:

- `README.md`
- `Wetools.xcodeproj/project.pbxproj`
- `Wetools/App/WetoolsApp.swift`
- `Wetools/App/AppDelegate.swift`
- `Wetools/Core/AppSettings.swift`
- `Wetools/Core/HotKey.swift`
- `Wetools/Managers/HotKeyManager.swift`
- `Wetools/Managers/PermissionManager.swift`
- `Wetools/Stores/JSONFileStore.swift`
- `Wetools/Views/SettingsView.swift`
- `Wetools/Views/PermissionStatusView.swift`
- `Wetools/Resources/Info.plist`
- `Wetools/Resources/Wetools.entitlements`

Modified files:

- None, except the previously added `AGENTS.md`.

How to run:

1. Open `Wetools.xcodeproj` in Xcode.
2. Select the `Wetools` scheme.
3. Run on an Apple Silicon Mac with macOS 13.0 or later.
4. Allow Wetools under System Settings > Privacy & Security > Screen Recording and Accessibility, then restart the app after changing either permission.

How to test:

1. Confirm the Wetools icon appears in the menu bar.
2. Open Settings from the menu.
3. Change shortcut settings and confirm they persist after relaunch.
4. Trigger the configured global shortcuts and confirm macOS notifications are posted.
5. Open permission rows and confirm they navigate to the relevant System Settings panes.

Known limitations:

- Shortcut capture now records the next key combination pressed in Settings.
- Basic screenshot and clipboard history are implemented.
- Scrolling screenshot, screen recording, launch at login, and polished annotation tools are planned for later phases.

## Local Development

Use the local scripts when you want to build, sign, and launch Wetools without GitHub Actions, GitHub Releases, DMG packaging, or Developer ID signing.

Requirements:

- Full Xcode installed and selected with `xcode-select`.
- The `Wetools` scheme available in either `Wetools.xcodeproj` or `Wetools.xcworkspace`.
- Local ad-hoc signing only. The scripts pass `CODE_SIGN_IDENTITY="-"`, `CODE_SIGN_STYLE=Manual`, and an empty `DEVELOPMENT_TEAM`.
- TODO: Replace the example bundle ID `com.yourname.Wetools` with the real bundle identifier before release.

Commands:

```sh
make run
```

Builds Debug into `./build/DevDerivedData`, ad-hoc signs the built app, stops any old Wetools process, and opens the built app directly.

```sh
make install
```

Builds Debug by default, ad-hoc signs the app, copies it to `/Applications/Wetools Dev.app`, stops the old process, and launches the installed app.

```sh
./scripts/dev_install.sh Release
```

Builds and installs the Release configuration locally.

```sh
make test
```

Runs `xcodebuild test` when a test target exists. If no test target exists yet, it falls back to `xcodebuild build` and prints a note.

```sh
make reset
```

Stops Wetools, removes `./build/DevDerivedData`, then asks before deleting Application Support data and UserDefaults.

```sh
make release-local
```

Builds the Release configuration, signs it with the configured identity, verifies the app bundle, and creates a DMG, ZIP, and SHA-256 checksums under `dist/`.

For a local ad-hoc build:

```sh
VERSION=0.0.2 BUNDLE_ID=com.yourname.Wetools make release-local
```

For public distribution, set `SIGN_IDENTITY` to a Developer ID Application certificate and notarize the resulting DMG before publishing.

Useful overrides:

```sh
SCHEME=Wetools make run
APP_NAME=Wetools ./scripts/dev_run.sh
BUNDLE_ID=com.yourname.Wetools make reset
```

Naming rules:

- Project: `Wetools.xcodeproj`
- Workspace, if present: `Wetools.xcworkspace`
- Scheme: `Wetools`
- App bundle: `Wetools.app`
- Local install path: `/Applications/Wetools Dev.app`
- Application Support directory: `~/Library/Application Support/Wetools`
- GitHub Release DMG name: `Wetools-{version}.dmg`
