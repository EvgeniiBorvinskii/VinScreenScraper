import AppKit
import Foundation

protocol SelectionOverlayDelegate: AnyObject {
    func selectionOverlayDidSelect(_ rect: CGRect)
    func selectionOverlayDidCancel()
}

/// Full-screen dimmed overlay for drag-selecting a screen region.
final class SelectionOverlayController: NSObject {
    weak var delegate: SelectionOverlayDelegate?

    private var windows: [SelectionWindow] = []
    private var isActive = false

    func begin() {
        guard !isActive else { return }
        isActive = true

        for screen in NSScreen.screens {
            let win = SelectionWindow(screen: screen)
            win.selectionDelegate = self
            windows.append(win)
            win.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func end() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        isActive = false
    }
}

extension SelectionOverlayController: SelectionOverlayDelegate {
    func selectionOverlayDidSelect(_ rect: CGRect) {
        end()
        delegate?.selectionOverlayDidSelect(rect)
    }

    func selectionOverlayDidCancel() {
        end()
        delegate?.selectionOverlayDidCancel()
    }
}

private final class SelectionWindow: NSWindow {
    weak var selectionDelegate: SelectionOverlayDelegate?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.setFrame(screen.frame, display: true)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        self.contentView = SelectionView(frame: screen.frame)
        (self.contentView as? SelectionView)?.onSelect = { [weak self] rect in
            self?.selectionDelegate?.selectionOverlayDidSelect(rect)
        }
        (self.contentView as? SelectionView)?.onCancel = { [weak self] in
            self?.selectionDelegate?.selectionOverlayDidCancel()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateTracking()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTracking()
    }

    private func updateTracking() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        guard let start = startPoint, let current = currentPoint else { return }

        let rect = CGRect(start, current)
        let path = NSBezierPath(rect: bounds)
        let hole = NSBezierPath(rect: rect)
        path.append(hole)
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        path.fill()

        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 2
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        defer {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
        }
        guard let start = startPoint, let current = currentPoint else { return }
        var rect = CGRect(start, current)
        // Convert from view (screen window) coords to global screen coords.
        if let win = window {
            rect = rect.offsetBy(dx: win.frame.origin.x, dy: win.frame.origin.y)
        }
        if rect.width < 8 || rect.height < 8 {
            onCancel?()
            return
        }
        onSelect?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        }
    }

    override var acceptsFirstResponder: Bool { true }
}

private extension CGRect {
    init(_ a: CGPoint, _ b: CGPoint) {
        self.init(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }
}
