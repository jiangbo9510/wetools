# Wetools

<p align="center">
  <img src="Wetools/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="96" alt="Wetools icon">
</p>

<p align="center">
  A native macOS menu bar utility for screenshots, screen recording, and clipboard history.
</p>

<p align="center">
  English | <a href="README_CN.md">简体中文</a>
</p>

## Features

### Clipboard history

- Automatically keeps a local history of copied text and images.
- Search and quickly restore previous clipboard entries.
- Selecting an older entry moves it to the top of the history.
- Optional automatic paste returns the selected content directly to the previously focused app.
- Configure the maximum number of saved entries.

### Screenshots

- Capture a selected area, an application window, or the full screen.
- Keep the selected region at normal brightness while dimming the surrounding screen.
- Move an unedited selection to capture another area with the same dimensions.
- Save the result as PNG or copy it directly to the clipboard.

### Screenshot annotation

- Rectangle, ellipse, line, arrow, and freehand drawing tools.
- Adjustable colors and line widths.
- Multiline text with standard font sizes and editable text boxes.
- Highlight, mosaic, watermark, and QR code recognition.
- Select, move, edit, or delete existing annotations.
- Pin a screenshot above other windows for reference.

### OCR and translation

- Extract text from screenshots using Apple Vision.
- Edit and copy recognized text from a standalone result window.
- Translate recognized text with the translation capability built into macOS.
- Choose a target language from the supported language menu.
- OCR and translation run through macOS and do not require an LLM API.

### Screen recording

- Record a selected area or the full screen as MP4.
- Optionally capture microphone audio, with a permission request on first use.
- Pause, resume, and stop from a compact floating control bar.
- Preview the recording, play or pause it, and seek through the timeline.
- Download the MP4 or copy it to the clipboard.

### Shortcuts and languages

- Customizable global shortcuts for the screenshot tool and clipboard history.
- Menu bar access remains available when a shortcut conflicts with another app.
- English and Simplified Chinese interfaces.
- The default language follows macOS: Chinese systems use Simplified Chinese, and other systems use English.

## Privacy

Wetools is designed around local macOS capabilities:

- Clipboard history is stored locally on your Mac.
- OCR uses Apple Vision.
- Translation uses the translation capability built into macOS.
- No LLM configuration or third-party API key is required.
- Screenshot, recording, and recognized text content is not uploaded by Wetools.

## Requirements

- Apple Silicon Mac
- macOS 13 or later
- macOS 14 or later is recommended for the complete screenshot experience
- Screen Recording permission for screenshots and screen recording
- Accessibility permission for automatic paste and simulated input

Permissions can be managed in **System Settings > Privacy & Security**. After changing Screen Recording permission, quit and reopen Wetools.

## Install

1. Download the latest DMG from [GitHub Releases](https://github.com/jiangbo9510/wetools/releases/latest).
2. Open the DMG and drag Wetools into Applications.
3. Launch Wetools and grant the requested macOS permissions.

Current public builds are ad-hoc signed and not notarized. On first launch, macOS may require approval in **System Settings > Privacy & Security**.

## Usage

Wetools stays in the macOS menu bar.

1. Open the screenshot tool from the menu bar or its global shortcut.
2. Choose Screenshot, Full Screen, Screen Recording, or Extract Text.
3. Drag to select an area, or point at an application window and click.
4. Use the floating controls to annotate, save, copy, pin, recognize text, or start recording.

Open Clipboard History from the menu bar or its shortcut, search for an entry, then press Enter or click it to restore and paste.

## Current limitations

- Scrolling screenshot is under development and its entry is currently hidden.
- Screen recordings are exported as MP4; GIF recording is not supported.
- Microphone recording requires permission the first time it is enabled.
- Public builds are not yet notarized with Apple Developer ID.

## Build from source

Open `Wetools.xcodeproj` in Xcode and run the `Wetools` scheme on an Apple Silicon Mac.

Useful commands:

```sh
make run
make test
make release-local
```

## License

No open-source license has been added yet. All rights are reserved unless a license is added to this repository.
