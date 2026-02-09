# Captioneer

On-device live captions for macOS:

- Listen from microphone
- Transcribe speech in real time
- Translate to a target language
- Show subtitles in overlay (Top / Bottom / Floating)
- Write live output to a `.txt` file for OBS

This repository currently contains:

- `CaptioneerStandalone/` -> the standalone Captioneer app (active project)
- `Textream/` -> original upstream base project kept for reference

## Privacy-First

Captioneer is designed to run locally:

- Speech recognition uses Apple on-device APIs (`SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`)
- Translation prefers Apple's local Translation framework when available
- OBS output is plain local file I/O
- No account, no server dependency in app flow

## Requirements

- macOS 15+
- Xcode 16+
- Apple Silicon or Intel Mac

## Quick Start (Run in Xcode)

```bash
git clone https://github.com/radioheavy/captioneer.git
cd captioneer
open CaptioneerStandalone/Captioneer.xcodeproj
```

Then in Xcode:

1. Select scheme `Captioneer`
2. Run (`Cmd+R`)
3. Grant `Microphone` and `Speech Recognition` permissions

## Install with Homebrew

After the first GitHub release is published:

```bash
brew tap radioheavy/captioneer https://github.com/radioheavy/captioneer
brew install --cask --appdir="$HOME/Applications" radioheavy/captioneer/captioneer
```

Open:

```bash
open ~/Applications/Captioneer.app
```

If macOS blocks first launch, run:

```bash
xattr -cr ~/Applications/Captioneer.app
```

## What Captioneer Does

1. Captures microphone audio
2. Produces live Turkish/English/etc transcription
3. Finalizes a sentence on:
   - speech engine final result, or
   - short silence window (to avoid waiting forever)
4. Translates finalized sentence to target language
5. Pushes subtitle lines to:
   - overlay panel
   - menu bar preview
   - OBS text file

## Overlay Modes

- `Top (Dynamic Island style)`
- `Bottom (Subtitle style)`
- `Floating (movable panel)`

Long lines wrap to next line (no forced single-line truncation).

## Settings

From the main app window:

- `Source Language`
- `Target Language`
- `Overlay Position`
- `Overlay Width` (slider, persistent)
- `Visible Lines`
- `OBS Output Path`
- `Context Buffer` (kept for tuning behavior)

## OBS Integration

Set `OBS Output Path` to a file, for example:

`~/Desktop/captioneer-live.txt`

In OBS:

1. Add `Text (GDI+/Freetype2)` source
2. Enable `Read from file`
3. Select the same `.txt` file

Captioneer updates this file whenever a new translated line is produced.

## Project Structure

```text
CaptioneerStandalone/
├── Captioneer.xcodeproj
└── Captioneer/
    ├── CaptioneerApp.swift
    ├── CaptionEngine.swift
    ├── CaptionOverlayView.swift
    ├── CaptioneerSettingsView.swift
    ├── OBSIntegration.swift
    ├── Info.plist
    ├── Captioneer.entitlements
    └── Assets.xcassets
```

## Current Behavior Notes

- Translation is sentence-oriented (not word-by-word scrolling translation)
- If speech engine delays finalization, silence-based finalize triggers translation
- Fallback translation path exists when system translation session is unavailable

## Troubleshooting

### "Listening var ama çeviri gelmiyor"

Check:

1. `Source Language` and `Target Language` are different
2. Microphone and Speech permissions are granted
3. Speak one full sentence, then pause briefly
4. Avoid heavy audio load apps if you see HAL overload logs

### Common macOS logs

You may see logs like:

- `ViewBridge ... NSViewBridgeErrorCanceled`
- `Unable to obtain a task name port right`
- `throwing -10877`

These are often benign/system-level and not always a direct app crash reason.

## Build from CLI

```bash
xcodebuild \
  -project CaptioneerStandalone/Captioneer.xcodeproj \
  -scheme Captioneer \
  -configuration Debug \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Roadmap Ideas

- Configurable overlay height and font scale in settings
- Explicit translation engine status badge in UI
- Export presets (streaming vs final-only)
- Packaging/notarization for release DMG

## License

MIT
