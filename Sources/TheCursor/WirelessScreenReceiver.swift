import AppKit
import Network
import CryptoKit
import CursorCore

/// All transport state is confined to queue. Only one authenticated phone is shown.
final class WirelessScreenReceiver {
    private var onFrame: ((NSImage, @escaping () -> Void) -> Void)?
    private var onStatus: ((String) -> Void)?
    private var onDisconnect: (() -> Void)?
    private let queue = DispatchQueue(label: "app.thecursor.screen-receiver", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var active: NWConnection?
    private var activeKey: SymmetricKey?
    private var key: SymmetricKey?
    private var generation = UUID()
    func start(token: String, onFrame: @escaping (NSImage, @escaping () -> Void) -> Void,
               onStatus: @escaping (String) -> Void, onDisconnect: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopOnQueue()
            self.onFrame = onFrame; self.onStatus = onStatus; self.onDisconnect = onDisconnect
            self.key = ScreenStreamProtocol.key(token: token)
            do {
                let parameters = NWParameters.tcp
                parameters.includePeerToPeer = true
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.service = NWListener.Service(name: ScreenStreamProtocol.serviceName(token: token), type: ScreenStreamProtocol.serviceType)
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, listener === self.listener else { return }
                    switch state {
                    case .ready: self.onStatus?("On iPhone, open The Cursor Connect and tap Share screen. Use the same Wi-Fi network.")
                    case .failed(let error): self.onStatus?("Wireless viewer unavailable: \(error.localizedDescription)")
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: self.queue)
            } catch { self.onStatus?("Could not start wireless viewer: \(error.localizedDescription)") }
        }
    }
    func stop() { queue.async { [weak self] in self?.stopOnQueue() } }
    private func stopOnQueue() {
        generation = UUID()
        listener?.cancel(); listener = nil
        let old = Array(connections.values), previous = active
        connections.removeAll(); active = nil
        if let previous, let activeKey,
           let sealed = try? ScreenStreamProtocol.seal(Data("stop".utf8), key: activeKey, sequence: .max) {
            previous.send(content: ScreenStreamProtocol.header(length: sealed.count) + sealed,
                completion: .contentProcessed { _ in previous.cancel() })
            queue.asyncAfter(deadline: .now() + 1) { previous.cancel() }
        } else { previous?.cancel() }
        old.filter { $0 !== previous }.forEach { $0.cancel() }
        activeKey = nil; key = nil
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 4, let key else { connection.cancel(); return }
        let id = ObjectIdentifier(connection), generation = self.generation
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, generation == self.generation else { return }
            if case .failed = state { self.remove(connection) }
            if case .cancelled = state { self.remove(connection) }
        }
        connection.start(queue: queue)
        // Bound unauthenticated connections; an idle LAN client must not occupy a slot forever.
        queue.asyncAfter(deadline: .now() + 10) { [weak self, weak connection] in
            guard let self, let connection, generation == self.generation,
                  self.connections[id] != nil, self.active !== connection else { return }
            self.remove(connection)
        }
        let server = ScreenStreamProtocol.nonce()
        connection.send(content: ScreenStreamProtocol.challenge(nonce: server, key: key), completion: .contentProcessed { [weak self, weak connection] error in
            guard let self, let connection, generation == self.generation else { return }
            guard error == nil else { self.remove(connection); return }
            self.read(connection, count: 64) { [weak self, weak connection] data in
                guard let self, let connection, generation == self.generation else { return }
                guard ScreenStreamProtocol.verify(data, prior: server, key: key), self.active == nil else { self.remove(connection); return }
                self.active = connection
                let session = ScreenStreamProtocol.sessionKey(key: key, server: server, client: Data(data.prefix(32)))
                self.activeKey = session
                self.receiveFrame(connection, key: session, sequence: 0, generation: generation)
            }
        })
    }
    private func read(_ connection: NWConnection, count: Int, completion: @escaping (Data) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self, weak connection] data, _, _, error in
            guard let self, let connection, self.connections[ObjectIdentifier(connection)] != nil else { return }
            guard error == nil, let data, data.count == count else { self.remove(connection); return }
            completion(data)
        }
    }
    private func receiveFrame(_ connection: NWConnection, key: SymmetricKey, sequence: UInt64, generation: UUID) {
        guard generation == self.generation, active === connection else { return }
        read(connection, count: 4) { [weak self, weak connection] header in
            guard let self, let connection, let length = try? ScreenStreamProtocol.frameLength(header) else {
                connection?.cancel(); return
            }
            self.read(connection, count: length) { [weak self, weak connection] data in
                guard let self, let connection, generation == self.generation, self.active === connection else { return }
                guard let jpeg = try? ScreenStreamProtocol.open(data, key: key, sequence: sequence),
                      let image = NSImage(data: jpeg), image.size.width > 0, image.size.height > 0,
                      image.size.width <= 4096, image.size.height <= 4096 else { self.remove(connection); return }
                // Wait until the UI consumes this frame before receiving another;
                // a busy main thread must not accumulate an unbounded image queue.
                self.onFrame?(image) { [weak self, weak connection] in
                    guard let self, let connection else { return }
                    self.queue.async { self.receiveFrame(connection, key: key, sequence: sequence + 1, generation: generation) }
                }
            }
        }
    }
    private func remove(_ connection: NWConnection) {
        guard connections.removeValue(forKey: ObjectIdentifier(connection)) != nil else { return }
        connection.cancel()
        if active === connection {
            active = nil; activeKey = nil; onDisconnect?()
            onStatus?("Wireless screen disconnected. Waiting for your iPhone…")
        }
    }
}
