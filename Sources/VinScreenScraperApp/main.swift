import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular (Dock) until Screen Recording works; then switch to menu-bar-only.
        ScreenRecordingPermission.applyActivationPolicyForPermissionState()
        let controller = AppController()
        self.controller = controller
        controller.start()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

autoreleasepool {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
