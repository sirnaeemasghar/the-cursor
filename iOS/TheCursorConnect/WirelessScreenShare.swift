import SwiftUI

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
import Network
import CoreImage
import CryptoKit
import UniformTypeIdentifiers

@available(iOS 27.0, *)
struct WirelessScreenControls: View {
    @ObservedObject var connection: PhoneConnection
    @StateObject private var share = PhoneScreenShare()
    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                Text("Wireless screen view").font(.system(size: 14, weight: .medium))
                Text(share.status).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(share.sharing ? "Stop sharing" : "Share screen") {
                    if share.sharing { share.stop() }
                    else if let token = connection.screenPairingToken { share.start(token: token) }
                }
                .buttonStyle(.bordered).disabled(connection.screenPairingToken == nil && !share.sharing)
                Text("Turn on Screen view on your Mac. Keep both devices on the same Wi-Fi. No cable, audio or saved recording.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(20).frame(maxWidth: .infinity)
        }
        .onChange(of: connection.screenPairingToken) { _, _ in share.stop() }
    }
}

@available(iOS 27.0, *)
final class PhoneScreenShare: NSObject, ObservableObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var sharing = false
    @Published private(set) var status = "Share your iPhone display with your paired Mac."
    private var stream: SCStream?
    private var selecting = false
    private let queue = DispatchQueue(label: "app.thecursor.screen-sender", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    // Transport and frame state belong exclusively to queue.
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var transportToken: String?
    private var pairingKey: SymmetricKey?
    private var sessionKey: SymmetricKey?
    private var sequence: UInt64 = 0
    private var sending = false
    private var lastFrame: TimeInterval = 0
    private var running = false
    private var generation = UUID()

    func start(token: String) {
        guard !sharing, !selecting else { return }
        let picker = SCContentSharingPicker.shared
        guard picker.isAvailable else { status = "Screen sharing is unavailable on this iPhone."; return }
        selecting = true
        var config = SCContentSharingPickerConfiguration()
        config.showsMicrophoneControl = false; config.showsCameraControl = false
        picker.defaultConfiguration = config
        picker.add(self); picker.isActive = true
        queue.async { [weak self] in
            self?.pairingKey = ScreenStreamProtocol.key(token: token)
        }
        // System permission is explicit and cannot be silently started by the Mac.
        status = "Choose Start Sharing in the iPhone screen-sharing prompt."
        picker.present()
        self.token = token
    }
    private var token: String?
    func stop() { finish("Screen sharing off") }
    private func finish(_ message: String) {
        selecting = false; sharing = false; status = message
        let picker = SCContentSharingPicker.shared
        picker.remove(self); picker.isActive = false
        let previous = stream; stream = nil; token = nil
        previous?.stopCapture { _ in }
        queue.async { [weak self] in
            guard let self else { return }
            self.running = false; self.generation = UUID()
            self.browser?.cancel(); self.browser = nil
            self.connection?.cancel(); self.connection = nil
            self.sessionKey = nil; self.pairingKey = nil; self.transportToken = nil; self.sending = false
        }
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async { self.finish("Screen sharing cancelled") }
    }
    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async { self.finish("Could not start screen sharing: \(error.localizedDescription)") }
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.selecting, let token = self.token else { return }
            self.selecting = false
            let config = SCStreamConfiguration()
            // Limit bandwidth and memory. Frames are independently decodable and late
            // frames are discarded while a network send is in flight.
            let rect = filter.contentRect
            let ratio = rect.height > 0 ? rect.width / rect.height : 393.0 / 852.0
            config.height = 1280; config.width = max(2, Int(1280 * ratio) / 2 * 2)
            config.capturesAudio = false
            let capture = SCStream(filter: filter, configuration: config, delegate: self)
            do {
                try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
                self.stream = capture; self.sharing = true
                self.status = "Starting wireless screen sharing…"
                capture.startCapture { [weak self, weak capture] error in
                    DispatchQueue.main.async {
                        guard let self, let capture, self.stream === capture else { return }
                        if let error { self.finish("Screen sharing failed: \(error.localizedDescription)"); return }
                        self.queue.async { self.running = true; self.discover(token: token) }
                    }
                }
            } catch { self.finish("Could not capture screen: \(error.localizedDescription)") }
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self, weak stream] in
            guard let self, stream === self.stream else { return }
            self.finish("Screen sharing stopped: \(error.localizedDescription)")
        }
    }
    private func publish(_ message: String) {
        DispatchQueue.main.async { [weak self] in guard let self, self.sharing else { return }; self.status = message }
    }
    private func discover(token: String) {
        guard running else { return }
        transportToken = token
        generation = UUID(); let generation = self.generation
        let parameters = NWParameters.tcp; parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: ScreenStreamProtocol.serviceType, domain: nil), using: parameters)
        self.browser = browser
        publish("Waiting for Screen view on your Mac. Keep both devices on the same Wi-Fi.")
        browser.stateUpdateHandler = { [weak self] state in
            guard let self, generation == self.generation else { return }
            if case .failed(let error) = state { self.publish("Local network unavailable: \(error.localizedDescription). Allow Local Network in Settings.") }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, generation == self.generation, self.connection == nil else { return }
            let expected = ScreenStreamProtocol.serviceName(token: token)
            if let endpoint = results.map(\.endpoint).first(where: {
                if case .service(let name, _, _, _) = $0 { return name == expected }; return false
            }) { self.connect(endpoint, token: token, generation: generation) }
        }
        browser.start(queue: queue)
    }
    private func connect(_ endpoint: NWEndpoint, token: String, generation: UUID) {
        let parameters = NWParameters.tcp; parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.connection === connection, generation == self.generation else { return }
            switch state {
            case .ready: self.authenticate(connection, token: token, generation: generation)
            case .failed, .cancelled: self.retry(connection, token: token, generation: generation)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { [weak self, weak connection] in
            guard let self, let connection, self.connection === connection, self.sessionKey == nil else { return }
            self.retry(connection, token: token, generation: generation)
        }
    }
    private func retry(_ old: NWConnection, token: String, generation: UUID) {
        guard self.generation == generation, connection === old else { return }
        connection = nil; old.cancel(); sessionKey = nil; sending = false
        browser?.cancel(); browser = nil
        self.generation = UUID(); let retryGeneration = self.generation
        publish("Wireless screen disconnected. Reconnecting…")
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.running, self.generation == retryGeneration else { return }
            self.discover(token: token)
        }
    }
    private func authenticate(_ connection: NWConnection, token: String, generation: UUID) {
        guard let pairingKey else { return }
        connection.receive(minimumIncompleteLength: 64, maximumLength: 64) { [weak self, weak connection] data, _, _, error in
            guard let self, let connection, generation == self.generation, self.connection === connection else { return }
            guard error == nil, let data, ScreenStreamProtocol.verify(data, key: pairingKey) else {
                self.publish("The Mac could not authenticate. Check your saved pairing.")
                self.retry(connection, token: token, generation: generation); return
            }
            let server = Data(data.prefix(32)), client = ScreenStreamProtocol.nonce()
            let session = ScreenStreamProtocol.sessionKey(key: pairingKey, server: server, client: client)
            connection.send(content: ScreenStreamProtocol.challenge(nonce: client, prior: server, key: pairingKey), completion: .contentProcessed { [weak self, weak connection] error in
                guard let self, let connection, self.connection === connection, generation == self.generation else { return }
                guard error == nil else { self.retry(connection, token: token, generation: generation); return }
                self.sessionKey = session; self.sequence = 0; self.lastFrame = 0
                self.publish("Sharing wirelessly with your Mac. You can leave this app.")
                // Only an authenticated stop message can end capture remotely.
                // Unexpected EOF/network loss retries while consent remains active.
                connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self, weak connection] header, _, _, error in
                    guard let self, let connection, self.connection === connection, generation == self.generation else { return }
                    guard error == nil, let header, let length = try? ScreenStreamProtocol.frameLength(header) else {
                        self.retry(connection, token: token, generation: generation); return
                    }
                    connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self, weak connection] data, _, _, error in
                        guard let self, let connection, self.connection === connection, generation == self.generation else { return }
                        guard error == nil, let data,
                              let message = try? ScreenStreamProtocol.open(data, key: session, sequence: .max),
                              message == Data("stop".utf8) else {
                            self.retry(connection, token: token, generation: generation); return
                        }
                        DispatchQueue.main.async { self.finish("Screen sharing stopped from your Mac.") }
                    }
                }
            })
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, running, !sending, let sessionKey, let connection,
              let token = transportToken, CMSampleBufferIsValid(sampleBuffer), let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 1.0 / 15 else { return }
        lastFrame = now; sending = true
        let generation = self.generation
        autoreleasepool {
            let source = CIImage(cvPixelBuffer: pixel)
            let scale = min(1, 1280 / max(source.extent.width, source.extent.height))
            let image = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let color = CGColorSpace(name: CGColorSpace.sRGB),
                  let jpeg = context.jpegRepresentation(of: image, colorSpace: color,
                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.55]),
                  let sealed = try? ScreenStreamProtocol.seal(jpeg, key: sessionKey, sequence: sequence) else { sending = false; return }
            sequence += 1
            let sentSequence = sequence
            queue.asyncAfter(deadline: .now() + 8) { [weak self, weak connection] in
                guard let self, let connection, self.generation == generation,
                      self.connection === connection, self.sending, self.sequence == sentSequence else { return }
                self.retry(connection, token: token, generation: generation)
            }
            connection.send(content: ScreenStreamProtocol.header(length: sealed.count) + sealed, completion: .contentProcessed { [weak self, weak connection] error in
                guard let self, let connection, generation == self.generation, self.connection === connection else { return }
                self.sending = false
                if error != nil { self.retry(connection, token: token, generation: generation) }
            })
        }
    }
}

#else
/// Older SDKs can build Bluetooth setup/control, but have no iOS capture module.
struct WirelessScreenControls: View {
    @ObservedObject var connection: PhoneConnection
    var body: some View {
        GlassCard {
            VStack(spacing: 10) {
                Text("Wireless screen view").font(.system(size: 14, weight: .medium))
                Text("This build supports Bluetooth control. For wireless screen viewing, rebuild with Xcode 27.2 or later and use iOS 27 or later.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(20).frame(maxWidth: .infinity)
        }
    }
}
#endif
