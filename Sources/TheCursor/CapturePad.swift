import AppKit
import SwiftUI
import CursorCore

struct CapturePad: NSViewRepresentable {
    @ObservedObject var bluetooth: BluetoothController
    var showsScreen = false
    func makeNSView(context: Context) -> PadView {
        let view = PadView()
        view.bluetooth = bluetooth
        bluetooth.releaseCapture = { [weak view] in view?.release() }
        return view
    }
    func updateNSView(_ nsView: PadView, context: Context) {
        nsView.showsScreen = showsScreen
        nsView.needsDisplay = true
    }
    static func dismantleNSView(_ view: PadView, coordinator: ()) { view.release() }
}

final class PadView: NSView {
    weak var bluetooth: BluetoothController?
    var showsScreen = false
    override var isOpaque: Bool { false }
    private var active = false
    private var pointer = Pointer()
    private var down = false
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var sleepObserver: NSObjectProtocol?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver); self.sleepObserver = nil }
        guard let window else { release(); return }
        window.acceptsMouseMovedEvents = true
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.willStartLiveResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.release() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.release() })
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in self?.release() }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in self?.release() })
    }
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let monitor { NSEvent.removeMonitor(monitor) }
        if active { CGAssociateMouseAndMouseCursorPosition(1); NSCursor.unhide() }
    }
    override func mouseDown(with event: NSEvent) {
        guard !active, let bluetooth, bluetooth.ready || bluetooth.preview else { return }
        let position = convert(event.locationInWindow, from: nil)
        pointer = Pointer(x: position.x / bounds.width, y: position.y / bounds.height)
        guard CGAssociateMouseAndMouseCursorPosition(0) == .success else {
            bluetooth.problem = "macOS could not capture the pointer. Click the pad again."; return
        }
        window?.makeFirstResponder(self)
        active = true; down = false; bluetooth.captured = true
        NSCursor.hide()
        bluetooth.move(pointer)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved,.leftMouseDragged,.leftMouseDown,.leftMouseUp,
            .rightMouseDown,.rightMouseUp,.scrollWheel,.keyDown,.keyUp,.flagsChanged]) { [weak self] event in
                guard let self, self.active else { return event }
                self.handle(event)
                return nil
            }
        needsDisplay = true
    }
    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown where event.keyCode == 53: release()
        case .keyDown: bluetooth?.key(event, down: true)
        case .keyUp: bluetooth?.key(event, down: false)
        case .flagsChanged: bluetooth?.modifiers(event)
        case .mouseMoved, .leftMouseDragged:
            pointer.move(dx: event.deltaX, dy: event.deltaY, width: bounds.width, height: bounds.height)
            bluetooth?.move(pointer); needsDisplay = true
        case .leftMouseDown: down = true; bluetooth?.move(pointer); bluetooth?.button(true)
        case .leftMouseUp:
            // The click that enters capture never becomes a tap on the phone.
            if down { down = false; bluetooth?.button(false) }
        case .scrollWheel:
            let wheel = Int(event.scrollingDeltaY.rounded())
            if wheel != 0 { bluetooth?.scroll(wheel, down: down) }
        default: break
        }
    }
    func release() {
        guard active else { bluetooth?.releaseButtons(); return }
        active = false; down = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        bluetooth?.captured = false; bluetooth?.releaseButtons()
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(bounds)
        if !showsScreen {
            NSColor.white.withAlphaComponent(0.025).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 28, yRadius: 28).fill()
        }
        if active {
            let p = NSPoint(x: pointer.x * bounds.width, y: pointer.y * bounds.height)
            NSColor.white.withAlphaComponent(0.15).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)).fill()
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
            ring.lineWidth = 2; ring.stroke()
        }
    }
}
