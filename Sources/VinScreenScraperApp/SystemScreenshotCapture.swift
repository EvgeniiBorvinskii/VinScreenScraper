import AppKit
import CoreGraphics
import Foundation

/// Captures a region using the system Screenshot UI (⌃⌘⇧4 → clipboard).
/// The capture is performed by macOS itself, so our app does not need Screen Recording.
enum SystemScreenshotCapture {
    enum CaptureError: LocalizedError {
        case accessibilityDenied
        case timedOut
        case noImage

        var errorDescription: String? {
            switch self {
            case .accessibilityDenied:
                return "Accessibility permission is required to trigger the system screenshot"
            case .timedOut:
                return "Timed out waiting for a screenshot (press Esc to cancel)"
            case .noImage:
                return "No image found on the clipboard"
            }
        }
    }

    static func ensureAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Triggers interactive screenshot-to-clipboard, then returns the image.
    static func captureRegionToImage(timeout: TimeInterval = 90) async throws -> CGImage {
        if !AXIsProcessTrusted() {
            _ = ensureAccessibility()
            // Give the user a moment if the prompt just appeared.
            try await Task.sleep(nanoseconds: 400_000_000)
            if !AXIsProcessTrusted() {
                throw CaptureError.accessibilityDenied
            }
        }

        let pb = NSPasteboard.general
        let beforeChange = pb.changeCount

        try postScreenshotToClipboardShortcut()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 150_000_000)
            if pb.changeCount == beforeChange { continue }
            if let image = imageFromPasteboard(pb) {
                return image
            }
            // Clipboard changed to something else (e.g. user cancelled into text) — keep waiting
            // until timeout unless change looks empty.
        }
        throw CaptureError.timedOut
    }

    static func imageFromPasteboard(_ pb: NSPasteboard = .general) -> CGImage? {
        if let data = pb.data(forType: .png),
           let img = NSBitmapImageRep(data: data)?.cgImage {
            return img
        }
        if let data = pb.data(forType: .tiff),
           let img = NSBitmapImageRep(data: data)?.cgImage {
            return img
        }
        if let objs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = objs.first {
            var rect = NSRect(origin: .zero, size: img.size)
            return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        return nil
    }

    /// ⌃⌘⇧4 — selection to clipboard
    private static func postScreenshotToClipboardShortcut() throws {
        let flags: CGEventFlags = [.maskCommand, .maskShift, .maskControl]
        // 0x15 = ANSI kVK_ANSI_4? Actually kVK_ANSI_4 is 0x15 (21). Yes.
        let keyCode: CGKeyCode = 0x15

        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else {
            throw CaptureError.accessibilityDenied
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
