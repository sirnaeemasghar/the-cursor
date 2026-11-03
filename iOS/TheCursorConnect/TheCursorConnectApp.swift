import SwiftUI
import CoreBluetooth
import AVFoundation

@main
struct TheCursorConnectApp: App {
    @StateObject private var connection = PhoneConnection()
    var body: some Scene {
        WindowGroup {
            ConnectView(connection: connection).preferredColorScheme(.dark)
                .onOpenURL { connection.pair($0.absoluteString) }
        }
    }
}

struct ConnectView: View {
    @ObservedObject var connection: PhoneConnection
    @Environment(\.scenePhase) private var scenePhase
    @State private var scanning = false
    @State private var showHelp = false
    var body: some View {
        ZStack {
            WaterBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    HStack {
                        Text("THE CURSOR").font(.system(size: 11, weight: .semibold)).tracking(2.5)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button { showHelp = true } label: {
                            Image(systemName: "questionmark.circle").font(.system(size: 19))
                        }.tint(.secondary).accessibilityLabel("Connection help")
                    }
                    .padding(.bottom, 30)
                    CursorLogo(size: 104).shadow(color: .cyan.opacity(0.13), radius: 36, y: 12)
                    VStack(spacing: 12) {
                        Text(connection.linked ? "A little closer." : "Meet your Mac.")
                            .font(.system(size: 34, weight: .medium)).tracking(-1)
                        Text(connection.linked ? "Your trackpad. Your keyboard. Your iPhone." : "Your iPhone, controlled from your Mac.")
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    GlassCard {
                        VStack(spacing: 12) {
                            HStack(spacing: 7) {
                                Circle().fill(connection.linked ? CursorPalette.aqua : .white.opacity(0.4))
                                    .frame(width: 6, height: 6)
                                Text(connection.linked ? "Setup linked" : connection.needsPairing ? "Finish pairing" : "Connecting")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            Text(connection.linked ? "You can leave this app. Move, swipe and type from your Mac." : connection.status)
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            if connection.needsPairing {
                                Text("Pair this Mac in iPhone Bluetooth settings, then try again.")
                                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("Try again") { connection.retrySetup() }.buttonStyle(.bordered)
                            }
                        }.padding(24).frame(maxWidth: .infinity)
                    }
                    VStack(spacing: 18) {
                        Button {
                            if connection.hasRememberedPairing && !connection.linked { connection.reconnect() }
                            else { scanning = true }
                        } label: {
                            Label(connection.linked ? "Pair another Mac" : connection.hasRememberedPairing ? "Reconnect" : "Scan Mac code", systemImage: connection.hasRememberedPairing && !connection.linked ? "arrow.triangle.2.circlepath" : "qrcode.viewfinder")
                                .font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent).tint(CursorPalette.aqua)
                        .foregroundStyle(CursorPalette.ink).controlSize(.large).buttonBorderShape(.capsule)
                        if connection.linked {
                            Button("End control on Mac") { connection.stopRemote() }
                                .font(.system(size: 13)).buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    if #available(iOS 27.0, *) { WirelessScreenControls(connection: connection) }
                    else { Text("Wireless screen sharing requires iOS 27 or later.").font(.caption).foregroundStyle(.secondary) }
                    if let error = connection.error {
                        Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center).textSelection(.enabled)
                    }
                    Text("Wireless control and optional screen sharing. Just your devices.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 16)
                    CreatorCredit()
                }
                .padding(.horizontal, 30).padding(.top, 22).padding(.bottom, 30)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { connection.resumeIfRemembered() }
        }
        .sheet(isPresented: $showHelp) {
            ZStack {
                WaterBackdrop().ignoresSafeArea()
                VStack(alignment: .leading, spacing: 22) {
                    Text("Make the connection.").font(.title2.weight(.semibold))
                    Text("1. Open The Cursor on your Mac.\n2. Scan its code here.\n3. Pair your Mac in iPhone Bluetooth settings.\n4. Enable AssistiveTouch in Accessibility → Touch.")
                        .font(.body).foregroundStyle(.secondary).lineSpacing(8)
                    Text(connection.status).font(.caption).foregroundStyle(CursorPalette.aqua)
                    if connection.hasRememberedPairing {
                        Button("Forget Mac", role: .destructive) { connection.forgetMac() }.disabled(connection.linked)
                        Text("End control before forgetting. Bluetooth pairing is managed separately in iPhone Settings.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Button("Done") { showHelp = false }.buttonStyle(.bordered)
                }.padding(30)
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                ScannerView { result in
                    scanning = false
                    switch result {
                    case .success(let text): connection.pair(text)
                    case .failure(let error): connection.error = error.localizedDescription
                    }
                }.ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Scan Mac code")
                    .toolbar { Button("Cancel") { scanning = false } }
            }
        }
    }
}

final class PhoneConnection: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var status = "Scan the code on your Mac once to pair."
    @Published var linked = false
    @Published var needsPairing = false
    @Published var hasRememberedPairing = false
    @Published var error: String?
    private var manager: CBCentralManager!
    var screenPairingToken: String? { code?.token }
    private var code: PairingCode?
    private var rememberedID: UUID?
    private var peripheral: CBPeripheral?
    private var hello: CBCharacteristic?
    private var command: CBCharacteristic?
    private var timeout: Timer?
    private var retryTimer: Timer?
    private var retryDelay: TimeInterval = 2
    private var stopping = false
    private var autoReconnect = true
    private var candidates: Set<UUID> = []

    override init() {
        super.init()
        do {
            if let saved = try PairingVault.read(RememberedMac.self, account: "remembered-mac") {
                code = try PairingCode.parse(saved.code.json)
                rememberedID = saved.peripheralID; hasRememberedPairing = true
                autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect") == nil || UserDefaults.standard.bool(forKey: "autoReconnect")
                status = autoReconnect ? "Reconnecting to your Mac…" : "Mac remembered. Tap Reconnect when ready."
                if autoReconnect { makeManager() }
            }
        } catch { self.error = "Saved pairing could not be read. Unlock your iPhone and try again." }
    }
    private func makeManager() {
        guard manager == nil else { return }
        manager = CBCentralManager(delegate: self, queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "app.thecursor.connect.central"])
    }
    func pair(_ text: String) {
        do {
            let parsed = try PairingCode.parse(text)
            closeLink()
            code = parsed; rememberedID = nil; error = nil; stopping = false
            candidates = []; needsPairing = false; autoReconnect = true
            UserDefaults.standard.set(true, forKey: "autoReconnect")
            status = "Finding your Mac…"
            makeManager()
            if manager.state == .poweredOn { scan() }
        } catch { self.error = "This is not a supported The Cursor pairing link." }
    }
    func reconnect() {
        guard code != nil else { return }
        autoReconnect = true; stopping = false
        UserDefaults.standard.set(true, forKey: "autoReconnect")
        makeManager()
        guard manager.state == .poweredOn else { status = "Waiting for Bluetooth…"; return }
        if let peripheral {
            if peripheral.state == .connected {
                if let hello, let code { sendHello(peripheral, hello: hello, code: code) }
                else { peripheral.discoverServices([CBUUID(string: PairingProtocol.service)]) }
                return
            }
            if peripheral.state == .connecting { return }
        }
        error = nil
        if let rememberedID, let known = manager.retrievePeripherals(withIdentifiers: [rememberedID]).first {
            connect(known)
        } else { candidates = []; scan() }
    }
    func forgetMac() {
        guard !linked else { error = "End control before forgetting this Mac."; return }
        autoReconnect = false; closeLink()
        do {
            try PairingVault.remove(account: "remembered-mac")
            code = nil; rememberedID = nil; hasRememberedPairing = false
            UserDefaults.standard.removeObject(forKey: "autoReconnect")
            needsPairing = false; error = nil; status = "Mac forgotten. Scan a new code to pair."
        } catch { self.error = "Could not remove the saved pairing. Try again." }
    }
    private func scan() {
        guard code != nil, autoReconnect else { return }
        manager.scanForPeripherals(withServices: [CBUUID(string: "1812")], options: nil)
        status = hasRememberedPairing ? "Waiting for your Mac. Your pairing is saved." : "Finding your Mac…"
        armTimeout()
    }
    private func connect(_ target: CBPeripheral) {
        timeout?.invalidate(); timeout = nil
        peripheral = target; target.delegate = self
        manager.stopScan(); manager.connect(target)
        status = "Waiting for your Mac over Bluetooth…"
        // CoreBluetooth keeps pending connections until the device becomes available.
        // Do not cancel them on a timer, especially while iOS is backgrounded.
    }
    private func armTimeout() {
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.stopping {
                self.error = "Stop was not confirmed. End the session from your Mac."
                self.closeLink(); return
            }
            self.closeLink(); self.scheduleReconnect()
        }
    }
    private func closeLink() {
        timeout?.invalidate(); timeout = nil; retryTimer?.invalidate(); retryTimer = nil
        manager?.stopScan()
        let previous = peripheral
        peripheral = nil; hello = nil; command = nil; linked = false
        previous?.delegate = nil
        if let previous { manager?.cancelPeripheralConnection(previous) }
    }
    private func scheduleReconnect() {
        guard autoReconnect, code != nil, !needsPairing else { return }
        status = "Waiting for your Mac. No need to scan again."
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: retryDelay, repeats: false) { [weak self] _ in self?.reconnect() }
        retryDelay = min(30, retryDelay * 2)
    }
    func stopRemote() {
        guard let peripheral, let command, peripheral.state == .connected else {
            error = "Your Mac is offline. End the session there when it is available."; return
        }
        stopping = true
        peripheral.writeValue(Data("stop".utf8), for: command, type: .withResponse)
        armTimeout()
    }
    func retrySetup() { needsPairing = false; reconnect() }
    func resumeIfRemembered() {
        if needsPairing { retrySetup(); return }
        if autoReconnect && code != nil && !linked { reconnect() }
    }
    private func sendHello(_ peripheral: CBPeripheral, hello: CBCharacteristic, code: PairingCode) {
        let screen = UIScreen.main.bounds.size
        let metadata = PhoneHello(token: code.token, name: UIDevice.current.model, width: screen.width, height: screen.height)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        status = "Restoring your connection…"
        armTimeout()
        peripheral.writeValue(data, for: hello, type: .withResponse)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: if autoReconnect { reconnect() }
        case .unauthorized: error = "Allow Bluetooth access in iPhone Settings."
        case .poweredOff: closeLink(); status = "Bluetooth is off. Your pairing is still saved."; linked = false
        default: closeLink(); status = "Bluetooth is temporarily unavailable. Your pairing is saved."; linked = false
        }
    }
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard autoReconnect, let rememberedID,
              let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first(where: { $0.identifier == rememberedID }) else { return }
        peripheral = restored; restored.delegate = self
    }
    func centralManager(_ central: CBCentralManager, didDiscover target: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let rememberedID { guard target.identifier == rememberedID else { return } }
        else {
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? target.name
            guard name == code?.name else { return }
        }
        guard peripheral == nil, candidates.insert(target.identifier).inserted else { return }
        connect(target)
    }
    func centralManager(_ central: CBCentralManager, didConnect target: CBPeripheral) {
        guard target === peripheral else { return }
        armTimeout()
        target.discoverServices([CBUUID(string: PairingProtocol.service)])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect target: CBPeripheral, error: Error?) {
        guard target === peripheral else { return }
        if isSecurityFailure(error) { requirePairingAttention(); return }
        closeLink(); scheduleReconnect()
    }
    private func isSecurityFailure(_ error: Error?) -> Bool {
        guard let failure = error as NSError? else { return false }
        if failure.domain == CBErrorDomain {
            return failure.code == CBError.peerRemovedPairingInformation.rawValue
                || failure.code == CBError.encryptionTimedOut.rawValue
        }
        return failure.domain == CBATTErrorDomain && [CBATTError.insufficientEncryption.rawValue,
            CBATTError.insufficientAuthentication.rawValue,
            CBATTError.insufficientEncryptionKeySize.rawValue].contains(failure.code)
    }
    private func requirePairingAttention() {
        closeLink(); needsPairing = true
        status = "Bluetooth pairing needs attention"
        error = "Bluetooth could not establish encryption. Check that this Mac is paired in iPhone Bluetooth settings, then tap Try again. No USB cable is required."
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral target: CBPeripheral, error: Error?) {
        guard target === peripheral else { return }
        if isSecurityFailure(error) { requirePairingAttention(); return }
        closeLink()
        // Re-issue a pending connection while iOS gives us this background callback.
        // The system may keep it pending until the remembered Mac advertises again.
        if autoReconnect && rememberedID != nil && central.state == .poweredOn { reconnect() }
        else { scheduleReconnect() }
    }
    func peripheral(_ target: CBPeripheral, didDiscoverServices error: Error?) {
        guard target === peripheral else { return }
        guard error == nil, let service = target.services?.first(where: { $0.uuid == CBUUID(string: PairingProtocol.service) }) else {
            self.error = error?.localizedDescription ?? "The Mac setup service is unavailable."
            closeLink(); scheduleReconnect(); return
        }
        target.discoverCharacteristics([CBUUID(string: PairingProtocol.hello), CBUUID(string: PairingProtocol.command)], for: service)
    }
    func peripheral(_ target: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard target === peripheral else { return }
        guard error == nil, let code else { closeLink(); scheduleReconnect(); return }
        hello = service.characteristics?.first { $0.uuid == CBUUID(string: PairingProtocol.hello) }
        command = service.characteristics?.first { $0.uuid == CBUUID(string: PairingProtocol.command) }
        guard let hello, command != nil else { self.error = "Mac setup service is incomplete."; closeLink(); scheduleReconnect(); return }
        sendHello(target, hello: hello, code: code)
    }
    func peripheral(_ target: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard target === peripheral else { return }
        if let error {
            let failure = error as NSError
            if isSecurityFailure(error) {
                requirePairingAttention()
            } else if characteristic === hello && failure.domain == CBATTErrorDomain && failure.code == CBATTError.insufficientAuthorization.rawValue {
                let wasRemembered = rememberedID != nil
                closeLink()
                if wasRemembered {
                    autoReconnect = false; code = nil; rememberedID = nil; hasRememberedPairing = false
                    try? PairingVault.remove(account: "remembered-mac")
                    status = "This Mac forgot the pairing. Scan its new code once."
                } else { scan() }
            } else {
                self.error = error.localizedDescription; closeLink(); scheduleReconnect()
            }
            return
        }
        timeout?.invalidate(); retryTimer?.invalidate()
        if characteristic === command && stopping {
            autoReconnect = false; UserDefaults.standard.set(false, forKey: "autoReconnect")
            status = "Control paused. Your Mac is remembered."
            closeLink()
        } else if characteristic === hello, let code {
            do {
                try PairingVault.save(RememberedMac(code: code, peripheralID: target.identifier), account: "remembered-mac")
                rememberedID = target.identifier; hasRememberedPairing = true
            } catch { self.error = "Connected, but pairing could not be saved. Keep the app open and retry later." }
            linked = true; needsPairing = false; retryDelay = 2
            if hasRememberedPairing { self.error = nil }
            status = "Connected. This Mac is remembered."
        }
    }
}

struct ScannerView: UIViewControllerRepresentable {
    let completion: (Result<String, Error>) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController(); controller.completion = completion; return controller
    }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) { controller.stop() }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var completion: ((Result<String, Error>) -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "the-cursor.qr-camera")
    private var layer: AVCaptureVideoPreviewLayer?
    private var completed = false
    private var cancelled = false
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else { self.fail("Allow camera access in Settings to scan the Mac QR code."); return }
            self.queue.async { self.configure() }
        }
    }
    private func configure() {
        guard !cancelled else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            fail("Camera unavailable. Scan with a physical iPhone."); return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { fail("QR scanning unavailable."); return }
        session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let layer = AVCaptureVideoPreviewLayer(session: self.session)
            layer.videoGravity = .resizeAspectFill; layer.frame = self.view.bounds
            self.view.layer.addSublayer(layer); self.layer = layer
        }
        session.startRunning()
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); layer?.frame = view.bounds }
    func stop() { queue.async { self.cancelled = true; if self.session.isRunning { self.session.stopRunning() } } }
    private func fail(_ text: String) {
        DispatchQueue.main.async {
            guard !self.completed else { return }; self.completed = true
            self.completion?(.failure(NSError(domain: "TheCursor.Scanner", code: 1, userInfo: [NSLocalizedDescriptionKey: text])))
        }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !completed, let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        // Ignore unrelated codes instead of closing the scanner.
        guard (try? PairingCode.parse(value)) != nil else { return }
        completed = true; stop(); completion?(.success(value))
    }
}
