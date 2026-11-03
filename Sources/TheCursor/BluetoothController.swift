import AppKit
import CoreBluetooth
import CursorCore

/// All delegate callbacks and UI changes run on the main queue.
final class BluetoothController: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    @Published var status = "Ready to set up"
    @Published var started = false
    @Published var ready = false
    @Published var keyboardReady = false
    private var keyboard = KeyboardState()
    @Published var captured = false
    @Published var phoneName = "iPhone 16"
    @Published var screenWidth = 393.0
    @Published var screenHeight = 852.0
    @Published var companionConnected = false
    @Published private(set) var hasRememberedPairing = false
    @Published var pairing = PairingCode()
    @Published var problem: String?
    @Published var preview = false
    private var held = false
    private var lastPointer = Pointer()
    private var relativeDrag: RelativeDrag?

    private var manager: CBPeripheralManager!
    private var pending: [CBMutableService] = []
    private var inputs: [UInt8: CBMutableCharacteristic] = [:]
    private var subscriptions: [UUID: Set<UInt8>] = [:]
    private var hosts: [UUID: CBCentral] = [:]
    private var selected: UUID?
    private var companion: UUID?
    private var helloCharacteristic: CBMutableCharacteristic!
    private var commandCharacteristic: CBMutableCharacteristic!
    private var protocolMode: CBMutableCharacteristic!
    private var controlPoint: CBMutableCharacteristic!
    private var outbox = ReportQueue()
    private var published = false
    private var sessionAllowed = true
    var releaseCapture: (() -> Void)?

    override init() {
        super.init()
        do {
            if let saved = try PairingVault.read(PairingCode.self, account: "mac-identity") {
                pairing = try PairingCode.parse(saved.json)
            }
            try PairingVault.save(pairing, account: "mac-identity")
        } catch { problem = "Could not access saved pairing. Unlock your Mac Keychain and retry." }
        if let phone = UserDefaults.standard.dictionary(forKey: "rememberedPhone"),
           let name = phone["name"] as? String, let width = phone["width"] as? Double,
           let height = phone["height"] as? Double,
           (try? PhoneHello(token: pairing.token, name: name, width: width, height: height).validate(token: pairing.token)) != nil {
            phoneName = name; screenWidth = width; screenHeight = height; hasRememberedPairing = true
        }
    }
    func resumeRememberedPairing() { if hasRememberedPairing && !started { start() } }
    func forgetPairing() {
        stop()
        do {
            try PairingVault.remove(account: "mac-identity")
            pairing = PairingCode()
            try PairingVault.save(pairing, account: "mac-identity")
            UserDefaults.standard.removeObject(forKey: "rememberedPhone")
            hasRememberedPairing = false
            status = "Pairing forgotten. Scan a new code to connect."
        } catch { problem = "Could not update saved pairing. Please retry." }
    }

    func start() {
        guard !started else { return }
        preview = false; started = true; sessionAllowed = true; problem = nil
        status = "Starting Bluetooth…"
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }
    func beginPreview() {
        guard !started else { return }
        preview = true
        status = "Local preview · no iPhone connected"
    }
    func stop() {
        releaseCapture?(); releaseButtons()
        sessionAllowed = false; ready = false; keyboardReady = false; preview = false; started = false
        manager?.stopAdvertising()
        manager?.removeAllServices()
        manager?.delegate = nil; manager = nil
        pending = []; inputs = [:]; subscriptions = [:]; hosts = [:]
        selected = nil; companion = nil; companionConnected = false; published = false
        outbox.clear() // Keep the remembered identity; ending a session is not forgetting it.
        status = "Session ended"
    }
    func move(_ pointer: Pointer) {
        if held {
            if relativeDrag == nil {
                relativeDrag = RelativeDrag(start: lastPointer, aspectRatio: screenWidth / screenHeight)
            }
            for delta in relativeDrag!.move(to: pointer) {
                enqueue(CursorReport.mouseID, CursorReport.mouse(down: true, dx: delta.x, dy: delta.y))
                if !held { break } // Overflow/cancel must not re-press a released touch.
            }
        } else {
            enqueue(CursorReport.absoluteID, pointer.absoluteReport)
        }
        lastPointer = pointer
    }
    func button(_ down: Bool) {
        if down && !held {
            relativeDrag = RelativeDrag(start: lastPointer, aspectRatio: screenWidth / screenHeight)
        }
        if !down { relativeDrag = nil }
        held = down
        enqueue(CursorReport.mouseID, CursorReport.mouse(down: down))
    }
    func scroll(_ amount: Int, down: Bool) {
        enqueue(CursorReport.mouseID, CursorReport.mouse(down: down, wheel: amount))
    }
    private func modifierByte(_ flags: NSEvent.ModifierFlags) -> UInt8 {
        var result: UInt8 = 0
        if flags.contains(.control) { result |= 1 }
        if flags.contains(.shift) { result |= 2 }
        if flags.contains(.option) { result |= 4 }
        if flags.contains(.command) { result |= 8 }
        return result
    }
    func key(_ event: NSEvent, down: Bool) {
        guard keyboardReady else { return }
        keyboard.setModifiers(modifierByte(event.modifierFlags))
        if down {
            guard !event.isARepeat, keyboard.press(macKeyCode: event.keyCode) else { return }
        } else { keyboard.release(macKeyCode: event.keyCode) }
        enqueue(CursorReport.keyboardID, keyboard.report)
    }
    func modifiers(_ event: NSEvent) {
        guard keyboardReady else { return }
        keyboard.setModifiers(modifierByte(event.modifierFlags))
        if event.keyCode == 57 { // Caps Lock is a toggle key, not a modifier bit.
            keyboard.press(macKeyCode: 57)
            enqueue(CursorReport.keyboardID, keyboard.report)
            keyboard.release(macKeyCode: 57)
        }
        enqueue(CursorReport.keyboardID, keyboard.report)
    }
    func releaseButtons() {
        held = false; relativeDrag = nil; keyboard.releaseAll()
        guard !preview, selected != nil else { return }
        outbox.release(); drain()
    }
    private func enqueue(_ id: UInt8, _ bytes: [UInt8]) {
        guard ready, !preview, sessionAllowed else { return }
        if !outbox.append(id: id, bytes: bytes) {
            problem = "Bluetooth input fell behind. Control was released; click the pad to resume."
            releaseCapture?()
        }
        drain()
    }
    private func drain() {
        guard let selected, let central = hosts[selected] else { outbox.clear(); return }
        while let item = outbox.items.first {
            guard let characteristic = inputs[item.id], subscriptions[selected]?.contains(item.id) == true
            else { outbox.pop(); continue }
            guard manager.updateValue(Data(item.bytes), for: characteristic, onSubscribedCentrals: [central]) else { return }
            outbox.pop()
        }
    }
    private func updateReady() {
        let hadKeyboard = keyboardReady
        let candidates = subscriptions.filter {
            $0.value.contains(CursorReport.absoluteID) && $0.value.contains(CursorReport.mouseID)
        }.map(\.key)
        // Never guess which of multiple phones should receive clicks.
        let next = candidates.count == 1 && sessionAllowed ? candidates.first : nil
        if selected != next {
            releaseCapture?(); releaseButtons(); outbox.clear(); selected = next
        }
        ready = next != nil
        keyboardReady = next.map { subscriptions[$0]?.contains(CursorReport.keyboardID) == true } ?? false
        if hadKeyboard && !keyboardReady { releaseCapture?(); releaseButtons() }
        if candidates.count > 1 {
            status = "Multiple Bluetooth hosts · disconnect the extra device"
        } else if !sessionAllowed {
            status = "Stopped from iPhone · end session to pair again"
        } else {
            status = ready ? (keyboardReady ? "iPhone mouse + keyboard connected" : "iPhone mouse connected · keyboard needs re-pairing") : "Waiting for iPhone Bluetooth pairing"
        }
    }
    private static func service(_ short: String) -> CBUUID {
        CBUUID(string: "0000\(short)-0000-1000-8000-00805F9B34FB")
    }
    private func buildServices() -> [CBMutableService] {
        let hid = CBMutableService(type: Self.service("1812"), primary: true)
        let info = CBMutableCharacteristic(type: CBUUID(string: "2A4A"), properties: .read,
            value: Data([0x11,0x01,0,0x02]), permissions: .readable)
        let map = CBMutableCharacteristic(type: CBUUID(string: "2A4B"), properties: .read,
            value: Data(CursorReport.descriptor), permissions: .readEncryptionRequired)
        controlPoint = CBMutableCharacteristic(type: CBUUID(string: "2A4C"), properties: .writeWithoutResponse,
            value: nil, permissions: .writeEncryptionRequired)
        protocolMode = CBMutableCharacteristic(type: CBUUID(string: "2A4E"), properties: [.read,.writeWithoutResponse],
            value: nil, permissions: [.readable,.writeable])
        var characteristics = [info, map, controlPoint!, protocolMode!]
        for id in [CursorReport.absoluteID, CursorReport.mouseID, CursorReport.keyboardID] {
            let input = CBMutableCharacteristic(type: CBUUID(string: "2A4D"), properties: [.read,.notify],
                value: nil, permissions: .readEncryptionRequired)
            input.descriptors = [CBMutableDescriptor(type: CBUUID(string: "2908"), value: Data([id,1]))]
            inputs[id] = input; characteristics.append(input)
        }
        hid.characteristics = characteristics
        let setup = CBMutableService(type: CBUUID(string: PairingProtocol.service), primary: true)
        helloCharacteristic = CBMutableCharacteristic(type: CBUUID(string: PairingProtocol.hello), properties: .write,
            value: nil, permissions: .writeEncryptionRequired)
        commandCharacteristic = CBMutableCharacteristic(type: CBUUID(string: PairingProtocol.command), properties: .write,
            value: nil, permissions: .writeEncryptionRequired)
        setup.characteristics = [helloCharacteristic, commandCharacteristic]
        let battery = CBMutableService(type: Self.service("180F"), primary: true)
        battery.characteristics = [CBMutableCharacteristic(type: CBUUID(string: "2A19"), properties: .read,
            value: Data([100]), permissions: .readable)]
        return [hid, setup, battery]
    }
    private func addNext() {
        guard let service = pending.first else {
            published = true
            manager.startAdvertising([
                CBAdvertisementDataLocalNameKey: "The Cursor",
                // Keep the legacy advertisement small enough for HID + full local name.
                // Companion discovers the custom setup service after connecting.
                CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "1812")]
            ])
            return
        }
        pending.removeFirst(); manager.add(service)
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral === manager else { return }
        releaseCapture?(); ready = false; keyboardReady = false; selected = nil; subscriptions = [:]; hosts = [:]; outbox.clear()
        companion = nil; companionConnected = false; published = false
        switch peripheral.state {
        case .poweredOn:
            peripheral.stopAdvertising(); peripheral.removeAllServices(); inputs = [:]
            pending = buildServices(); addNext()
        case .unauthorized: status = "Allow Bluetooth in System Settings → Privacy & Security"
        case .poweredOff: status = "Turn on Bluetooth on your Mac"
        case .unsupported: status = "This Mac does not support Bluetooth LE peripherals"
        default: status = "Bluetooth is temporarily unavailable"
        }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { problem = error.localizedDescription; status = "Could not publish Bluetooth services"; return }
        addNext()
    }
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error { problem = error.localizedDescription; status = "Bluetooth advertising failed" }
        else { updateReady() }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard let id = inputs.first(where: { $0.value === characteristic })?.key else { return }
        hosts[central.identifier] = central
        subscriptions[central.identifier, default: []].insert(id)
        updateReady()
        // Prime only the new subscription; never release buttons on another host.
        _ = peripheral.updateValue(Data(count: CursorReport.length(for: id)),
            for: inputs[id]!, onSubscribedCentrals: [central])
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard let id = inputs.first(where: { $0.value === characteristic })?.key else { return }
        subscriptions[central.identifier]?.remove(id); updateReady()
    }
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) { drain() }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let data: Data
        if request.characteristic === protocolMode { data = Data([1]) }
        else if let id = inputs.first(where: { $0.value === request.characteristic })?.key {
            data = Data(count: CursorReport.length(for: id))
        } else { peripheral.respond(to: request, withResult: .attributeNotFound); return }
        guard request.offset <= data.count else { peripheral.respond(to: request, withResult: .invalidOffset); return }
        request.value = data.subdata(in: request.offset..<data.count)
        peripheral.respond(to: request, withResult: .success)
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let first = requests.first else { return }
        var newHello: (PhoneHello, UUID)?
        var stopRequested = false
        // Validate the complete batch before changing session state.
        for request in requests {
            guard request.offset == 0, let data = request.value, data.count <= 1024 else {
                peripheral.respond(to: first, withResult: .invalidAttributeValueLength); return
            }
            if request.characteristic === helloCharacteristic {
                guard companion == nil || companion == request.central.identifier,
                      let hello = try? JSONDecoder().decode(PhoneHello.self, from: data),
                      (try? hello.validate(token: pairing.token)) != nil else {
                    peripheral.respond(to: first, withResult: .insufficientAuthorization); return
                }
                newHello = (hello, request.central.identifier)
            } else if request.characteristic === commandCharacteristic {
                guard request.central.identifier == companion, data == Data("stop".utf8) else {
                    peripheral.respond(to: first, withResult: .insufficientAuthorization); return
                }
                stopRequested = true
            } else if request.characteristic === protocolMode {
                guard data == Data([1]) else { peripheral.respond(to: first, withResult: .requestNotSupported); return }
            } else if request.characteristic === controlPoint {
                guard data.count == 1, data[0] <= 1 else {
                    peripheral.respond(to: first, withResult: .invalidAttributeValueLength); return
                }
            } else { peripheral.respond(to: first, withResult: .writeNotPermitted); return }
        }
        if let (hello, id) = newHello {
            releaseCapture?(); companion = id; companionConnected = true
            phoneName = hello.name; screenWidth = hello.width; screenHeight = hello.height
            UserDefaults.standard.set(["name": hello.name, "width": hello.width, "height": hello.height], forKey: "rememberedPhone")
            hasRememberedPairing = true
        }
        if stopRequested {
            releaseCapture?(); releaseButtons(); sessionAllowed = false
            manager.stopAdvertising(); updateReady()
        }
        peripheral.respond(to: first, withResult: .success)
    }
}
