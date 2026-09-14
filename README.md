# VIN Screen Scraper

macOS menu bar app: press **⌘⇧1**, select a screen region, and VIN numbers are copied to the clipboard.

## Features

- Global hotkey **Command + Shift + 1** → region selection
- OCR (Apple Vision + optional Tesseract) on the selected area
- VIN extraction with **ISO 3779 check digit** validation
- Multiple VINs → column with commas (configurable)
- Menu bar icon + **Executor** status (running / paused)
- Options: sound, notifications, strict validation, clipboard format, launch at login
- **Stop Executor** / **Quit and Stop**

## Build & Run

```bash
chmod +x scripts/build.sh
./scripts/build.sh
open App/VinScreenScraper.app
```

On first use, allow **Screen Recording**:
System Settings → Privacy & Security → Screen Recording → VIN Screen Scraper.

## Usage

1. The app appears in the menu bar (viewfinder icon).
2. Press **⌘⇧1** (or “Select Region…” in the menu).
3. Drag to select the area with VINs, then release.
4. VINs are on the clipboard.

Default format:

```
1HGCM82633A004352,
5YJSA1E26HF000001
```

> Sample `WVWZZZ3CZWE012345` from older notes **fails** the ISO check digit — it is intentionally skipped in strict mode.
