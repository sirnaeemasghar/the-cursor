import AppKit
import AVFoundation
import CoreMediaIO
import SwiftUI

/// Optional local screen viewing over authenticated Wi-Fi or USB. Never discovers or opens the Mac webcam.
final class ScreenViewer: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Source: String, CaseIterable { case wireless = "Wi-Fi", usb = "USB" }
    @Published private(set) var source: Source = .wireless
    @Published private(set) var wirelessImage: NSImage?
    private let wireless = WirelessScreenReceiver()
    private var token: String?
    private var wirelessGeneration = UUID()
    struct Phone: Identifiable { let id: String; let name: String }
    @Published private(set) var enabled = false
    @Published private(set) var hasFrames = false
    @Published private(set) var status = "Screen viewing off"
    @Published private(set) var phones: [Phone] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var frameSize: CGSize?
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.thecursor.usb-screen", qos: .userInitiated)
    private var requested = false
    private var activeID: String?
    private var chosenID: String?
    private var dimensions = CGSize.zero
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in self?.refresh() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
            object: session, queue: nil) { [weak self] note in
                let message = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "Capture stopped. Reconnect your iPhone."
                self?.queue.async { [weak self] in
                    self?.stopSession()
                    self?.publish(message)
                }
            })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Called by the UI. Permission is requested only after an explicit ON toggle.
    func setEnabled(_ value: Bool) {
        enabled = value
        hasFrames = false; frameSize = nil; wirelessImage = nil
        wirelessGeneration = UUID(); wireless.stop()
        if !value {
            status = "Screen viewing off"
            queue.async { [weak self] in self?.requested = false; self?.stopSession() }
            return
        }
        if source == .wireless { beginWireless(); return }
        status = "Preparing screen view…"
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.enabled else { return }
                    if granted { self.begin() }
                    else { self.status = "Allow Camera access in System Settings → Privacy & Security to view the USB iPhone screen." }
                }
            }
        default: status = "Allow Camera access in System Settings → Privacy & Security to view the USB iPhone screen."
        }
    }
    func configure(token: String) {
        guard self.token != token else { return }
        self.token = token
        if enabled && source == .wireless { setEnabled(true) }
    }
    func setSource(_ value: Source) {
        guard source != value else { return }
        let wasEnabled = enabled
        setEnabled(false); source = value
        if wasEnabled { setEnabled(true) }
    }
    private func beginWireless() {
        queue.async { [weak self] in self?.requested = false; self?.stopSession() }
        guard let token else { status = "Connect your iPhone to set up wireless viewing."; return }
        let generation = wirelessGeneration
        status = "Starting wireless viewer…"
        let onFrame: (NSImage, @escaping () -> Void) -> Void = { [weak self] image, consumed in
            DispatchQueue.main.async {
                defer { consumed() }
                guard let self, self.enabled, self.source == .wireless, self.wirelessGeneration == generation else { return }
                self.wirelessImage = image; self.frameSize = image.size
                self.hasFrames = true; self.status = "Live screen · Wi-Fi · Encrypted"
            }
        }
        let onStatus: (String) -> Void = { [weak self] message in
            DispatchQueue.main.async {
                guard let self, self.enabled, self.source == .wireless, self.wirelessGeneration == generation else { return }
                self.status = message
            }
        }
        let onDisconnect: () -> Void = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.wirelessGeneration == generation else { return }
                self.hasFrames = false; self.wirelessImage = nil; self.frameSize = nil
            }
        }
        wireless.start(token: token, onFrame: onFrame, onStatus: onStatus, onDisconnect: onDisconnect)
    }
    func select(_ id: String?) {
        selectedID = id
        queue.async { [weak self] in self?.chosenID = id; self?.refresh() }
    }
    private func begin() {
        queue.async { [weak self] in
            guard let self else { return }
            self.requested = true
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var allow: UInt32 = 1
            let result = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
                &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)
            guard result == noErr else {
                self.publish("macOS could not enable USB iPhone capture (\(result)).")
                return
            }
            self.refresh()
        }
    }
    private func refresh() {
        guard requested else { return }
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed,
            position: .unspecified).devices.filter { $0.isConnected && $0.modelID.localizedCaseInsensitiveContains("iOS") }
        let choices = devices.map { Phone(id: $0.uniqueID, name: $0.localizedName) }
        DispatchQueue.main.async { [weak self] in self?.phones = choices }
        let device: AVCaptureDevice?
        if devices.count == 1 { device = devices.first }
        else { device = devices.first { $0.uniqueID == chosenID } }
        guard let device else {
            stopSession()
            publish(devices.isEmpty ? "Connect your unlocked iPhone with a USB data cable and tap Trust." : "Choose the iPhone to view in Connection help.")
            return
        }
        guard activeID != device.uniqueID || !session.isRunning else { return }
        stopSession()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: queue)
            session.beginConfiguration()
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                publish("This iPhone is not available for screen capture. Close other USB capture apps and retry.")
                return
            }
            session.addInput(input); session.addOutput(output)
            session.commitConfiguration()
            activeID = device.uniqueID
            DispatchQueue.main.async { [weak self] in self?.selectedID = device.uniqueID }
            publish("Waiting for iPhone video… Keep the phone unlocked.")
            session.startRunning()
        } catch { publish("Could not open iPhone screen: \(error.localizedDescription)") }
    }
    private func stopSession() {
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
        activeID = nil; dimensions = .zero
        DispatchQueue.main.async { [weak self] in
            guard let self, self.source == .usb || !self.enabled else { return }
            self.hasFrames = false; self.frameSize = nil
        }
    }
    private func publish(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled, self.source == .usb else { return }
            self.status = message
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard requested, let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let size = CMVideoFormatDescriptionGetDimensions(format)
        let next = CGSize(width: Int(size.width), height: Int(size.height))
        guard next != dimensions, next.width > 0, next.height > 0 else { return }
        dimensions = next
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled, self.source == .usb else { return }
            self.frameSize = next; self.hasFrames = true; self.status = "Live screen · USB"
        }
    }
}

struct PhoneScreenPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView(); view.preview.session = session; return view
    }
    func updateNSView(_ view: PreviewView, context: Context) { view.preview.session = session }
    final class PreviewView: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true; preview.videoGravity = .resizeAspect
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() { super.layout(); preview.frame = bounds }
    }
}
