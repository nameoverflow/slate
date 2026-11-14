# Slate

A minimal, native macOS screenshot and annotation utility built with Swift, AppKit, and ScreenCaptureKit.

## Features

- **Menu Bar Resident & Global Hotkey**: Lives quietly in the macOS menu bar (`LSUIElement`), triggered globally via **`⌃⇧A`** (customizable in Settings).
- **Window Highlight + Dual Selection Mode**:
  - Dims the screen and highlights the topmost window under the cursor in real time.
  - **Click** once to capture the highlighted window.
  - **Drag** to draw a custom rectangular region; adjust with 8 resize handles or drag to move.
- **Floating Annotation Toolbar**:
  - Shapes: Rectangle, Ellipse (`Shift` for circle/square), Arrow (`Shift` for 45° snap)
  - Freehand brush with smooth quadratic curves
  - Inline text annotation with full CJK/IME support (`Enter` to commit, `Shift+Enter` for newline)
  - 7 colors, 3 stroke weights, and Undo (`⌘Z`)
- **Quick Export**:
  - **Double-click** the selection, press **`Enter`**, or hit **`⌘C`** / **Copy** to copy Retina-resolution output to the clipboard.
  - **`⌘S`** / **Save** to export as PNG or JPEG.
  - **`Esc`** to cancel.
- **Launch at Login & Silent Mode**:
  - Built-in **Launch at Login** toggle (`~/Library/LaunchAgents/com.slate.screenshot.plist`) and optional **Hide Menu Bar Icon** mode (reopen `Slate.app` anytime to access Settings), with single-instance guard.

## Requirements

- macOS 14.0+ (built & tested on macOS 26.5 / Apple Silicon)
- Swift 6.0+ / Xcode Command Line Tools

## Build & Install

```bash
./build_app.sh
cp -R dist/Slate.app /Applications/
open /Applications/Slate.app
```

Run tests:

```bash
swift run SlateTests
```

Grant **Screen Recording** permission in **System Settings → Privacy & Security → Screen Recording** on first capture.
