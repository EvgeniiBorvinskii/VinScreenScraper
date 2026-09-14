import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError, Equatable {
    case noDisplay
    case captureFailed
    case permissionDenied
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found"
        case .captureFailed: return "Failed to capture screen"
        case .permissionDenied: return "Screen Recording permission is required in System Settings"
        case .cancelled: return "Selection cancelled"
        }
    }
}

enum ScreenCaptureService {
    /// Native macOS interactive selection via `/usr/sbin/screencapture -i`.
    /// More reliable on macOS 15 than custom overlays + ScreenCaptureKit.
    static func captureInteractive() async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let image = try runScreencaptureInteractive()
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Capture a rect in global Cocoa coordinates (bottom-left origin).
    static func capture(rect: CGRect) async throws -> CGImage {
        if let image = try? await captureWithScreencaptureRect(rect) {
            return image
        }
        if ScreenRecordingPermission.hasAccess(), #available(macOS 14.0, *) {
            if let image = try? await captureWithSC(rect: rect) {
                return image
            }
        }
        if let image = try? captureLegacy(rect: rect), !isMostlyBlank(image) {
            return image
        }
        throw ScreenRecordingPermission.hasAccess()
            ? ScreenCaptureError.captureFailed
            : ScreenCaptureError.permissionDenied
    }

    // MARK: - screencapture CLI

    private static func runScreencaptureInteractive() throws -> CGImage {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vin_capture_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive selection, -x silent, -t png
        proc.arguments = ["-i", "-x", "-t", "png", url.path]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()

        try proc.run()
        proc.waitUntilExit()

        // User pressed Esc / cancelled
        if proc.terminationStatus != 0 {
            throw ScreenCaptureError.cancelled
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ScreenCaptureError.cancelled
        }
        guard let image = loadCGImage(from: url) else {
            // Often means TCC blocked capture (empty/missing bitmap).
            throw ScreenCaptureError.permissionDenied
        }
        if isMostlyBlank(image) {
            throw ScreenCaptureError.permissionDenied
        }
        return image
    }

    private static func captureWithScreencaptureRect(_ rect: CGRect) async throws -> CGImage {
        // screencapture -R uses top-left global coordinates, points (not pixels).
        let mainH = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }.height
        let x = Int(rect.origin.x.rounded())
        let y = Int((mainH - rect.origin.y - rect.height).rounded())
        let w = Int(rect.width.rounded())
        let h = Int(rect.height.rounded())
        guard w > 2, h > 2 else { throw ScreenCaptureError.cancelled }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vin_rect_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", "-t", "png", "-R", "\(x),\(y),\(w),\(h)", url.path]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0,
              let image = loadCGImage(from: url),
              !isMostlyBlank(image) else {
            throw ScreenCaptureError.permissionDenied
        }
        return image
    }

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Black / empty frames usually mean TCC denied the capture.
    private static func isMostlyBlank(_ image: CGImage) -> Bool {
        let w = min(image.width, 64)
        let h = min(image.height, 64)
        guard w > 0, h > 0 else { return true }
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return false }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var nonBlack = 0
        let step = 4
        let total = w * h
        for i in stride(from: 0, to: total, by: step) {
            let o = i * 4
            if ptr[o] > 12 || ptr[o + 1] > 12 || ptr[o + 2] > 12 {
                nonBlack += 1
            }
        }
        return nonBlack < max(3, total / (step * 40))
    }

    // MARK: - Fallbacks

    private static func captureLegacy(rect: CGRect) throws -> CGImage {
        let mainH = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }.height
        let cgRect = CGRect(
            x: rect.origin.x,
            y: mainH - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        guard let image = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .nominalResolution]
        ) else {
            throw ScreenCaptureError.captureFailed
        }
        return image
    }

    @available(macOS 14.0, *)
    private static func captureWithSC(rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { display in
            let frame = CGRect(
                x: display.frame.origin.x,
                y: display.frame.origin.y,
                width: display.frame.width,
                height: display.frame.height
            )
            return frame.intersects(rect)
        }) ?? content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let displayFrame = display.frame
        let globalTopY = displayFrame.origin.y + displayFrame.height
        config.sourceRect = CGRect(
            x: rect.origin.x - displayFrame.origin.x,
            y: globalTopY - (rect.origin.y + rect.height),
            width: rect.width,
            height: rect.height
        )
        config.width = max(1, Int(rect.width * scale))
        config.height = max(1, Int(rect.height * scale))
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
