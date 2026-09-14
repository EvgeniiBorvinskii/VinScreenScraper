import AppKit
import Carbon
import Foundation

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyManagerDidTrigger()
}

/// Global ⌘⇧1 via Carbon — works without Accessibility for the hotkey itself.
final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var isRegistered = false

    private let hotKeyID = EventHotKeyID(signature: OSType(0x5354564E), id: 1) // 'STVN'

    func start() {
        guard !isRegistered else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if hkID.id == manager.hotKeyID.id {
                    DispatchQueue.main.async {
                        manager.delegate?.hotkeyManagerDidTrigger()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )

        guard status == noErr else {
            NSLog("InstallEventHandler failed: \(status)")
            return
        }

        // ⌘⇧1 → keyCode 18 is "1" on ANSI keyboards
        let modifiers = UInt32(cmdKey | shiftKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_1),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            isRegistered = true
        } else {
            NSLog("RegisterEventHotKey failed: \(registerStatus)")
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        isRegistered = false
    }

    deinit {
        stop()
    }
}
