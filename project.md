# Wetools Project Architecture

## Project Overview

Wetools is a native macOS menu bar productivity app built with Swift, SwiftUI, and AppKit. The current product surface focuses on screenshots, screen recording, clipboard history, permissions, localization, and AI/OCR configuration.

The app is intentionally structured around small responsibility-specific types:

- `AppDelegate` owns app lifecycle, menu bar setup, and top-level window orchestration.
- `AppSettings` owns user configuration and persists settings through the Store layer.
- Managers own stateful macOS workflows such as global hotkeys, clipboard polling, screenshots, recording, and permissions.
- Services own reusable system or network operations such as ScreenCaptureKit screenshots, Keychain access, OCR, and LLM clients.
- Views are SwiftUI presentation surfaces and should delegate side effects to settings, managers, stores, or services.

## Runtime Shape

```text
WetoolsApp
└── AppDelegate
    ├── AppSettings
    │   └── JSONFileStore<SettingsSnapshot>
    ├── LocalizationManager
    ├── HotKeyManager
    ├── ClipboardManager
    │   └── JSONFileStore<ClipboardHistorySnapshot>
    ├── ScreenshotManager
    │   ├── ScreenCaptureScreenshotService
    │   ├── ScreenRecordingManager
    │   └── ScreenshotPreviewView
    ├── PermissionManager
    └── LLMProviderStore
        ├── JSONFileStore<LLMProviderSnapshot>
        └── KeychainService
```

`WetoolsApp` registers `AppDelegate` through `@NSApplicationDelegateAdaptor` and exposes an empty SwiftUI Settings scene because the real settings window is created and controlled by AppKit. `AppDelegate` sets the app activation policy to accessory mode, creates the `NSStatusItem`, registers global hotkeys, starts clipboard monitoring, and opens SwiftUI views inside AppKit windows or panels.

## Directory Layout

```text
Wetools/
├── App/
├── Core/
├── Localization/
├── Managers/
├── Models/
├── Resources/
├── Services/
├── Stores/
└── Views/
```

### App

`Wetools/App/WetoolsApp.swift` is the SwiftUI entry point. `Wetools/App/AppDelegate.swift` is the app shell and composition root. It constructs shared objects, wires callbacks, and presents windows:

- Settings window: `SettingsView`
- Clipboard history panel: `ClipboardHistoryPanelView`
- Screenshot and recording flows: delegated to `ScreenshotManager`

Broad business logic should remain out of `AppDelegate`; new features should be added as dedicated managers, services, or stores and only wired here.

### Core

`Wetools/Core/AppSettings.swift` is the observable source of user preferences. It stores screenshot and clipboard hotkeys, clipboard history size, launch-at-login flag, auto-paste flag, save directory, app language, and OCR language preference. Every published setting persists on change.

`Wetools/Core/HotKey.swift` defines the serializable hotkey value types used by settings, views, and `HotKeyManager`. It wraps Carbon key codes and modifier flags while exposing user-facing display text.

### Localization

`LocalizationManager` is an observable runtime string lookup service. It supports system language, Simplified Chinese, and English through `zh-Hans.lproj` and `en.lproj`. Views observe it so language changes update visible UI without restarting the app.

Visible UI strings should use localization keys instead of hard-coded text.

### Managers

Managers own side-effect-heavy app workflows.

`HotKeyManager` registers Carbon global hotkeys for screenshot and clipboard history actions. It listens for `kEventHotKeyPressed`, maps the action ID back to an enum, and calls `onScreenshot` or `onClipboardHistory` on the main actor.

`ClipboardManager` polls `NSPasteboard.general` on a timer, deduplicates content with SHA-256 hashes, stores text/file/image history, writes selected items back to the pasteboard, and optionally simulates `Command-V`. Clipboard metadata is persisted as JSON, while clipboard images are stored as PNG files.

`ScreenshotManager` coordinates the screenshot tool. It owns the action panel, area selection window, scrolling screenshot controls, recording controls, preview window, and Escape-key cancellation. Actual screenshot capture is delegated to `ScreenCaptureScreenshotService`; recording is delegated to `ScreenRecordingManager`.

`ScreenRecordingManager` records selected screen regions as MP4 with ScreenCaptureKit and AVFoundation. It supports cursor capture, optional system audio, pasteboard export, and trimming.

`PermissionManager` checks and requests Accessibility, Screen Recording, Microphone, and Camera permissions, then opens the relevant System Settings pane.

### Services

Services are reusable lower-level operations.

`ScreenCaptureScreenshotService` wraps ScreenCaptureKit screenshot capture. It captures full screen or selected regions on macOS 14.0+ and returns `NSImage`.

`OCRManager` uses Apple Vision local OCR with language hints from `OCRLanguagePreference`.

`LLMProviderStore` manages configured AI providers. Provider metadata is stored in JSON, but API keys are stored in Keychain through `KeychainService`.

`LLMClient` defines the client protocol for chat, vision analysis, and connection tests. Current implementations include OpenAI-compatible providers, Ollama, and custom HTTP endpoints. Only OpenAI-compatible chat and provider connection tests have concrete behavior at this stage; unsupported methods throw explicit errors.

`KeychainService` wraps generic password storage using the app bundle identifier as the Keychain service. The fallback bundle ID remains `com.yourname.Wetools` with a TODO to replace it before release.

### Stores

`JSONFileStore<Value: Codable>` is the generic local persistence layer. It reads and writes pretty-printed sorted JSON under:

```text
~/Library/Application Support/Wetools/
```

Current JSON files include settings, clipboard history, and LLM provider metadata.

### Models

Models are Codable value types shared between managers, services, stores, and views:

- `ClipboardItem`, `ClipboardItemKind`, `ClipboardHistorySnapshot`
- `LLMProvider`, `LLMProviderType`, `LLMProviderSnapshot`
- `OCRLanguagePreference`, `OCRResult`, `OCRObservation`

### Views

Views are SwiftUI presentation components:

- `SettingsView` provides general settings, shortcut settings, permissions, and AI/OCR settings tabs.
- `HotKeyRecorderView` captures hotkey input for settings.
- `PermissionStatusView` renders permission state and action buttons.
- `ClipboardHistoryPanelView` renders the floating clipboard picker.
- `ScreenshotActionPanelView` renders screenshot mode choices.
- `ScreenshotPreviewView` renders the screenshot editor, annotation toolbar, OCR action, QR detection, save, copy, and close controls.
- `OCRResultView` renders OCR output and text/LLM actions.
- `AISettingsView` manages AI provider configuration.

Views may own temporary UI state, but persistence, permission checks, capture, recording, OCR, and network calls should stay in the existing settings, manager, store, or service types.

## Main Feature Flows

### App Launch

1. `WetoolsApp` creates `AppDelegate`.
2. `AppDelegate.applicationDidFinishLaunching` switches the app to accessory mode.
3. Notification authorization is requested.
4. The menu bar item is configured.
5. Global shortcuts are registered.
6. Clipboard monitoring starts.

### Settings Updates

1. User changes a value in `SettingsView`.
2. `AppSettings` publishes and persists the new snapshot.
3. `settings.onChange` in `AppDelegate` refreshes localization, menu text, window title, and hotkey registration.

### Screenshot Shortcut

1. `HotKeyManager` receives the screenshot hotkey event.
2. `AppDelegate.triggerScreenshot` calls `ScreenshotManager.showActionPanel`.
3. The action panel lets the user choose area capture, full-screen capture, scrolling screenshot, recording, OCR, or cancel.
4. Normal area/full-screen capture uses `ScreenCaptureScreenshotService`.
5. Captured images open in `ScreenshotPreviewView` for annotation, OCR, saving, or copying.

### Clipboard History

1. `ClipboardManager` polls the pasteboard every 0.6 seconds.
2. It reads file URLs, text, or images.
3. Content is hashed to deduplicate entries.
4. Metadata is saved to `clipboard-history.json`; images are saved under `ClipboardImages`.
5. `ClipboardHistoryPanelView` lets users restore, paste, delete, or clear entries.

### Screen Recording

1. `ScreenshotManager` asks the user to select a recording region.
2. `ScreenRecordingManager.start` configures ScreenCaptureKit and AVAssetWriter for MP4 output.
3. The recording panel controls start, stop, trim, reveal, and cancel.
4. Finished recordings are written to the configured save directory and copied to the pasteboard as file URLs.

### AI and OCR

1. `AISettingsView` edits `LLMProvider` records through `LLMProviderStore`.
2. Provider metadata is persisted to `llm-providers.json`.
3. API keys are saved to Keychain and referenced by `apiKeySecretRef`.
4. `ScreenshotPreviewView` runs local OCR through `OCRManager`.
5. `OCRResultView` can use the active provider through `LLMClientFactory` for supported text actions.

## Permissions

Wetools uses macOS privacy APIs directly:

- Screen Recording: needed for ScreenCaptureKit screenshots and recording.
- Accessibility: needed for simulated paste and scrolling screenshot automation.
- Microphone: optional for screen recording with audio.
- Camera: optional for camera overlay during recording.

Permission state is exposed by `PermissionManager` and surfaced in Settings.

## Local Data

Local application data is intentionally kept under `Application Support/Wetools`.

```text
~/Library/Application Support/Wetools/settings.json
~/Library/Application Support/Wetools/clipboard-history.json
~/Library/Application Support/Wetools/llm-providers.json
~/Library/Application Support/Wetools/ClipboardImages/
```

API keys are not written to JSON; they are stored in macOS Keychain.

## Build and Run

The default Xcode container is `Wetools.xcodeproj`. If `Wetools.xcworkspace` is added later, local scripts prefer it.

Common commands:

```sh
make run
make install
make test
make reset
```

`make run` builds Debug into `build/DevDerivedData`, ad-hoc signs the app, stops any running Wetools process, and opens the built app.

`make install` installs the app to:

```text
/Applications/Wetools Dev.app
```

`make test` runs `xcodebuild test` when test targets exist, otherwise it falls back to `xcodebuild build`.

## Current Boundaries and Limitations

- The app currently has no committed test target; local test scripts fall back to building.
- ScreenCaptureKit screenshot capture requires macOS 14.0+.
- Screen recording requires macOS 13.0+.
- Scrolling screenshots are implemented as repeated captures with optional synthetic scroll events and image stitching; results depend on the target app and content stability.
- Launch at login is present in settings but disabled in the UI.
- Some LLM client methods are intentionally stubbed with `unsupportedProvider`.
- The example bundle ID `com.yourname.Wetools` must be replaced before release.

## Maintenance Rules

- Keep app lifecycle and window composition in `AppDelegate`, but keep feature logic out of it.
- Add new persistent settings to `AppSettings.Snapshot` and keep default values backward-compatible.
- Route JSON/file persistence through `JSONFileStore` or a dedicated Store type.
- Keep secrets in Keychain, not JSON.
- Keep macOS system workflows in manager/service types.
- Keep UI strings localized.
- Keep async UI state updates on the main actor.
- Handle system API failures with explicit user-visible errors or logged diagnostics.
