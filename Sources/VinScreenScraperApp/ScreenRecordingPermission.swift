import AppKit
import CoreGraphics
import Foundation

enum ScreenRecordingPermission {
    static func hasAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestAccess() -> Bool {
        if hasAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Keep a Dock icon until Screen Recording works — TCC is flaky for menu-bar-only ad-hoc apps.
    static func applyActivationPolicyForPermissionState() {
        if hasAccess() {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func showDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Not Working"
        alert.informativeText = """
        macOS 15 often keeps the toggle ON for an OLD build, while this new build is still blocked.

        Do this exactly:

        1. Quit VIN Screen Scraper completely
        2. Open System Settings → Privacy & Security → Screen Recording
        3. Remove EVERY “VinScreenScraper” row (−)
        4. Click (+) and select:
           /Applications/VinScreenScraper.app
        5. Turn it ON
        6. Open /Applications/VinScreenScraper.app again

        Important: use the copy in /Applications only (not Desktop).
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openSystemSettings()
        case .alertSecondButtonReturn:
            let app = URL(fileURLWithPath: "/Applications/VinScreenScraper.app")
            if FileManager.default.fileExists(atPath: app.path) {
                NSWorkspace.shared.activateFileViewerSelecting([app])
            } else {
                openSystemSettings()
            }
        default:
            break
        }
    }
}
