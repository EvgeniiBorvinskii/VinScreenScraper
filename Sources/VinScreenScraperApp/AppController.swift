import AppKit
import Foundation
import AudioToolbox
import VINCore

final class AppController: NSObject {
    private let statusBar = StatusBarController()
    private let hotkey = HotkeyManager()
    private let settings = AppSettings.shared

    private var isSelecting = false
    private var executorPaused = false
    private var permissionTimer: Timer?

    func start() {
        NotificationHelper.requestPermission()
        ScreenRecordingPermission.applyActivationPolicyForPermissionState()

        if !ScreenRecordingPermission.hasAccess() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = ScreenRecordingPermission.requestAccess()
                ScreenRecordingPermission.applyActivationPolicyForPermissionState()
            }
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                ScreenRecordingPermission.applyActivationPolicyForPermissionState()
                if ScreenRecordingPermission.hasAccess() {
                    self?.permissionTimer?.invalidate()
                    self?.permissionTimer = nil
                }
            }
        }

        statusBar.onToggleHotkey = { [weak self] enabled in
            guard let self else { return }
            if enabled && !self.executorPaused {
                self.hotkey.start()
            } else {
                self.hotkey.stop()
            }
        }
        statusBar.onPauseExecutor = { [weak self] in
            self?.executorPaused = true
            self?.hotkey.stop()
        }
        statusBar.onResumeExecutor = { [weak self] in
            guard let self else { return }
            self.executorPaused = false
            if self.settings.hotkeyEnabled {
                self.hotkey.start()
            }
        }
        statusBar.onQuit = { [weak self] in
            self?.permissionTimer?.invalidate()
            self?.hotkey.stop()
            NSApp.terminate(nil)
        }
        statusBar.onManualCapture = { [weak self] in
            self?.beginSelection()
        }
        statusBar.onOpenScreenRecordingSettings = {
            ScreenRecordingPermission.openSystemSettings()
        }
        statusBar.onOCRClipboard = { [weak self] in
            self?.ocrClipboardImage()
        }
        statusBar.isExecutorRunning = { [weak self] in
            !(self?.executorPaused ?? true)
        }

        hotkey.delegate = self

        if settings.hotkeyEnabled {
            hotkey.start()
        }

        statusBar.rebuildMenu()
    }

    private func beginSelection() {
        guard !executorPaused else {
            notifyFailure("Executor is paused — resume it from the menu bar")
            return
        }
        guard !isSelecting else { return }
        isSelecting = true

        Task { @MainActor in
            defer { self.isSelecting = false }
            do {
                let image: CGImage
                if ScreenRecordingPermission.hasAccess() {
                    // Preferred when TCC works (Developer-signed build).
                    _ = ScreenRecordingPermission.requestAccess()
                    do {
                        image = try await ScreenCaptureService.captureInteractive()
                    } catch {
                        // Fall back to system screenshot UI (no Screen Recording needed).
                        image = try await SystemScreenshotCapture.captureRegionToImage()
                    }
                } else {
                    // Bypass broken Screen Recording TCC entirely.
                    image = try await SystemScreenshotCapture.captureRegionToImage()
                }
                await self.processImage(image)
            } catch SystemScreenshotCapture.CaptureError.accessibilityDenied {
                self.showAccessibilityHelp()
            } catch ScreenCaptureError.cancelled {
                // Esc — ignore
            } catch SystemScreenshotCapture.CaptureError.timedOut {
                // User likely cancelled — ignore
            } catch ScreenCaptureError.permissionDenied {
                // Try system screenshot path once more.
                do {
                    let image = try await SystemScreenshotCapture.captureRegionToImage()
                    await self.processImage(image)
                } catch {
                    ScreenRecordingPermission.showDeniedAlert()
                }
            } catch {
                self.notifyFailure(error.localizedDescription)
            }
        }
    }

    private func ocrClipboardImage() {
        guard let image = SystemScreenshotCapture.imageFromPasteboard() else {
            notifyFailure("No image on the clipboard. Use ⌃⌘⇧4 first, then try again.")
            return
        }
        Task { @MainActor in
            await self.processImage(image)
        }
    }

    private func showAccessibilityHelp() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        VIN Screen Scraper triggers the system screenshot tool (⌃⌘⇧4). That capture is done by macOS, so Screen Recording is not required.

        Enable Accessibility:
        System Settings → Privacy & Security → Accessibility → VinScreenScraper → ON
        """
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func processImage(_ image: CGImage) async {
        do {
            let ocr = try await OCRService.recognize(in: image)
            var result = VINExtractor.extract(from: ocr.primaryText, strictCheckDigit: settings.strictVIN)

            if result.vins.isEmpty {
                var collected: [String] = []
                var seen = Set<String>()
                for alt in ocr.alternateLines {
                    for vin in VINExtractor.extract(from: alt, strictCheckDigit: settings.strictVIN).vins {
                        if seen.insert(vin).inserted { collected.append(vin) }
                    }
                }
                if !collected.isEmpty {
                    result = VINExtractor.Result(vins: collected, rawText: ocr.primaryText)
                }
            }

            var debugText = ocr.primaryText
            if result.vins.isEmpty, let tess = OCRService.recognizeWithTesseract(image: image), !tess.isEmpty {
                debugText = ocr.primaryText + "\n" + tess
                result = VINExtractor.extract(from: tess, strictCheckDigit: settings.strictVIN)
            }

            guard !result.vins.isEmpty else {
                var msg = "No VIN found in the selected region"
                if settings.showRawOCROnFailure {
                    let preview = debugText.replacingOccurrences(of: "\n", with: " ")
                    let short = preview.count > 120 ? String(preview.prefix(120)) + "…" : preview
                    msg += "\nOCR: \(short)"
                }
                notifyFailure(msg)
                return
            }

            let formatted = VINExtractor.formatForClipboard(result.vins, style: settings.copyFormat)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(formatted, forType: .string)

            settings.lastCopiedVINs = result.vins
            statusBar.rebuildMenu()

            if settings.soundEnabled {
                AudioServicesPlaySystemSound(1001)
            }

            let body = result.vins.count == 1
                ? result.vins[0]
                : "Copied \(result.vins.count) VINs\n" + result.vins.joined(separator: "\n")
            notifySuccess(body)
        } catch {
            notifyFailure(error.localizedDescription)
        }
    }

    private func notifySuccess(_ body: String) {
        guard settings.notificationEnabled else { return }
        NotificationHelper.notify(title: "VIN Copied", body: body)
    }

    private func notifyFailure(_ body: String) {
        if settings.soundEnabled {
            NSSound.beep()
        }
        guard settings.notificationEnabled else { return }
        NotificationHelper.notify(title: "VIN Scraper", body: body)
    }
}

extension AppController: HotkeyManagerDelegate {
    func hotkeyManagerDidTrigger() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard !self.executorPaused, self.settings.hotkeyEnabled else { return }
            self.beginSelection()
        }
    }
}
