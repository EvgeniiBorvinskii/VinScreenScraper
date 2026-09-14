import AppKit
import Foundation
import UserNotifications
import VINCore

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let settings = AppSettings.shared

    var onToggleHotkey: ((Bool) -> Void)?
    var onPauseExecutor: (() -> Void)?
    var onResumeExecutor: (() -> Void)?
    var onQuit: (() -> Void)?
    var onManualCapture: (() -> Void)?
    var onOpenScreenRecordingSettings: (() -> Void)?
    var onOCRClipboard: (() -> Void)?
    var isExecutorRunning: () -> Bool = { true }

    private var executorPaused = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "VIN Scraper")
            button.image?.isTemplate = true
            button.toolTip = "VIN Screen Scraper — ⌘⇧1"
        }
        rebuildMenu()
    }

    func setPaused(_ paused: Bool) {
        executorPaused = paused
        if let button = statusItem.button {
            button.appearsDisabled = paused
            button.toolTip = paused
                ? "VIN Scraper — paused"
                : "VIN Screen Scraper — ⌘⇧1"
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let statusTitle = executorPaused ? "● Executor: paused" : "● Executor: running"
        let statusRow = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        menu.addItem(statusRow)

        menu.addItem(NSMenuItem.separator())

        let capture = NSMenuItem(title: "Select Region…", action: #selector(manualCapture), keyEquivalent: "1")
        capture.keyEquivalentModifierMask = [.command, .shift]
        capture.target = self
        menu.addItem(capture)

        let fromClip = NSMenuItem(title: "Extract VINs from Clipboard Image", action: #selector(ocrClipboard), keyEquivalent: "")
        fromClip.target = self
        menu.addItem(fromClip)

        menu.addItem(NSMenuItem.separator())

        // Options submenu
        let options = NSMenu()

        let hotkey = NSMenuItem(
            title: "Hotkey ⌘⇧1",
            action: #selector(toggleHotkey),
            keyEquivalent: ""
        )
        hotkey.state = settings.hotkeyEnabled ? .on : .off
        hotkey.target = self
        options.addItem(hotkey)

        let sound = NSMenuItem(title: "Sound on Copy", action: #selector(toggleSound), keyEquivalent: "")
        sound.state = settings.soundEnabled ? .on : .off
        sound.target = self
        options.addItem(sound)

        let notif = NSMenuItem(title: "Notifications", action: #selector(toggleNotifications), keyEquivalent: "")
        notif.state = settings.notificationEnabled ? .on : .off
        notif.target = self
        options.addItem(notif)

        let strict = NSMenuItem(title: "Strict VIN Check (check digit)", action: #selector(toggleStrict), keyEquivalent: "")
        strict.state = settings.strictVIN ? .on : .off
        strict.target = self
        options.addItem(strict)

        let rawOCR = NSMenuItem(title: "Show OCR Text on Failure", action: #selector(toggleRawOCR), keyEquivalent: "")
        rawOCR.state = settings.showRawOCROnFailure ? .on : .off
        rawOCR.target = self
        options.addItem(rawOCR)

        options.addItem(NSMenuItem.separator())

        let formatMenu = NSMenu()
        for format in AppSettings.CopyFormat.allCases {
            let item = NSMenuItem(title: format.title, action: #selector(selectFormat(_:)), keyEquivalent: "")
            item.representedObject = format.storageValue
            item.state = settings.copyFormat == format ? .on : .off
            item.target = self
            formatMenu.addItem(item)
        }
        let formatItem = NSMenuItem(title: "Clipboard Format", action: nil, keyEquivalent: "")
        formatItem.submenu = formatMenu
        options.addItem(formatItem)

        if #available(macOS 13.0, *) {
            let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
            login.state = settings.isLaunchAtLoginEnabled ? .on : .off
            login.target = self
            options.addItem(login)
        }

        let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        optionsItem.submenu = options
        menu.addItem(optionsItem)

        let screenPerm = NSMenuItem(
            title: "Screen Recording Settings…",
            action: #selector(openScreenRecording),
            keyEquivalent: ""
        )
        screenPerm.target = self
        menu.addItem(screenPerm)

        // Last VINs
        if !settings.lastCopiedVINs.isEmpty {
            let lastMenu = NSMenu()
            for vin in settings.lastCopiedVINs.prefix(10) {
                let item = NSMenuItem(title: vin, action: #selector(recopyVIN(_:)), keyEquivalent: "")
                item.representedObject = vin
                item.target = self
                lastMenu.addItem(item)
            }
            lastMenu.addItem(NSMenuItem.separator())
            let copyAll = NSMenuItem(title: "Copy All Again", action: #selector(recopyAll), keyEquivalent: "")
            copyAll.target = self
            lastMenu.addItem(copyAll)
            let lastItem = NSMenuItem(title: "Recent VINs", action: nil, keyEquivalent: "")
            lastItem.submenu = lastMenu
            menu.addItem(lastItem)
        }

        menu.addItem(NSMenuItem.separator())

        if executorPaused {
            let resume = NSMenuItem(title: "Resume Executor", action: #selector(resumeExecutor), keyEquivalent: "")
            resume.target = self
            menu.addItem(resume)
        } else {
            let pause = NSMenuItem(title: "Stop Executor", action: #selector(pauseExecutor), keyEquivalent: "")
            pause.target = self
            menu.addItem(pause)
        }

        let quit = NSMenuItem(title: "Quit and Stop", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func manualCapture() { onManualCapture?() }

    @objc private func ocrClipboard() { onOCRClipboard?() }

    @objc private func openScreenRecording() { onOpenScreenRecordingSettings?() }

    @objc private func toggleHotkey() {
        settings.hotkeyEnabled.toggle()
        onToggleHotkey?(settings.hotkeyEnabled)
        rebuildMenu()
    }

    @objc private func toggleSound() {
        settings.soundEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleNotifications() {
        settings.notificationEnabled.toggle()
        if settings.notificationEnabled {
            NotificationHelper.requestPermission()
        }
        rebuildMenu()
    }

    @objc private func toggleStrict() {
        settings.strictVIN.toggle()
        rebuildMenu()
    }

    @objc private func toggleRawOCR() {
        settings.showRawOCROnFailure.toggle()
        rebuildMenu()
    }

    @objc private func selectFormat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let format = AppSettings.CopyFormat(storageValue: raw) else { return }
        settings.copyFormat = format
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        _ = settings.setLaunchAtLogin(!settings.isLaunchAtLoginEnabled)
        rebuildMenu()
    }

    @objc private func recopyVIN(_ sender: NSMenuItem) {
        guard let vin = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(vin, forType: .string)
    }

    @objc private func recopyAll() {
        let text = VINExtractor.formatForClipboard(settings.lastCopiedVINs, style: settings.copyFormat)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func pauseExecutor() {
        executorPaused = true
        onPauseExecutor?()
        setPaused(true)
    }

    @objc private func resumeExecutor() {
        executorPaused = false
        onResumeExecutor?()
        setPaused(false)
    }

    @objc private func quitApp() {
        onQuit?()
    }
}

enum NotificationHelper {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
