import Foundation
import ServiceManagement
import VINCore

extension VINCopyFormat: CaseIterable {
    public static var allCases: [VINCopyFormat] {
        [.columnWithCommas, .columnOnly, .commaSeparated]
    }

    var title: String {
        switch self {
        case .columnWithCommas: return "Column with commas"
        case .columnOnly: return "Column only"
        case .commaSeparated: return "Comma-separated (one line)"
        }
    }

    var storageValue: String {
        switch self {
        case .columnWithCommas: return "column_commas"
        case .columnOnly: return "column"
        case .commaSeparated: return "comma"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "column_commas": self = .columnWithCommas
        case "column": self = .columnOnly
        case "comma": self = .commaSeparated
        default: return nil
        }
    }
}

final class AppSettings {
    static let shared = AppSettings()

    typealias CopyFormat = VINCopyFormat

    // titles via extension below

    private let defaults = UserDefaults.standard

    private enum Key {
        static let hotkeyEnabled = "hotkeyEnabled"
        static let soundEnabled = "soundEnabled"
        static let notificationEnabled = "notificationEnabled"
        static let strictVIN = "strictVIN"
        static let copyFormat = "copyFormat"
        static let showRawOCR = "showRawOCR"
        static let lastVINs = "lastVINs"
    }

    var hotkeyEnabled: Bool {
        get { defaults.object(forKey: Key.hotkeyEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.hotkeyEnabled) }
    }

    var soundEnabled: Bool {
        get { defaults.object(forKey: Key.soundEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.soundEnabled) }
    }

    var notificationEnabled: Bool {
        get { defaults.object(forKey: Key.notificationEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notificationEnabled) }
    }

    var strictVIN: Bool {
        get { defaults.object(forKey: Key.strictVIN) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.strictVIN) }
    }

    var showRawOCROnFailure: Bool {
        get { defaults.object(forKey: Key.showRawOCR) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showRawOCR) }
    }

    var copyFormat: CopyFormat {
        get {
            let raw = defaults.string(forKey: Key.copyFormat) ?? CopyFormat.columnWithCommas.storageValue
            return CopyFormat(storageValue: raw) ?? .columnWithCommas
        }
        set { defaults.set(newValue.storageValue, forKey: Key.copyFormat) }
    }

    var lastCopiedVINs: [String] {
        get { defaults.stringArray(forKey: Key.lastVINs) ?? [] }
        set { defaults.set(newValue, forKey: Key.lastVINs) }
    }

    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return true
            } catch {
                NSLog("Launch at login failed: \(error)")
                return false
            }
        }
        return false
    }

    var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}
