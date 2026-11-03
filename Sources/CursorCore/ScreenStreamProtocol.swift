import Foundation
import CryptoKit

/// Local screen-stream v1. Fresh mutual challenges bind every connection to the
/// QR pairing secret. AES-GCM authenticates each frame and its ordered sequence.
public enum ScreenStreamProtocol {
    public static let serviceType = "_cursor-screen._tcp"
    public static let maximumFrameBytes = 1_048_576
    public static let handshakeBytes = 64
    public static func key(token: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(("TheCursor.screen.v1:" + token).utf8)))
    }
    public static func serviceName(token: String) -> String {
        "Cursor-" + SHA256.hash(data: Data(token.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    public static func nonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max) }
        return Data(bytes)
    }
    public static func challenge(nonce: Data, prior: Data = Data(), key: SymmetricKey) -> Data {
        nonce + Data(HMAC<SHA256>.authenticationCode(for: Data("challenge".utf8) + prior + nonce, using: key))
    }
    public static func verify(_ message: Data, prior: Data = Data(), key: SymmetricKey) -> Bool {
        guard message.count == handshakeBytes else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(message.suffix(32),
            authenticating: Data("challenge".utf8) + prior + message.prefix(32), using: key)
    }
    public static func sessionKey(key: SymmetricKey, server: Data, client: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: server + client,
            info: Data("TheCursor.screen.session.v1".utf8), outputByteCount: 32)
    }
    public static func sequence(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
    public static func seal(_ jpeg: Data, key: SymmetricKey, sequence: UInt64) throws -> Data {
        guard !jpeg.isEmpty, jpeg.count <= maximumFrameBytes - 28 else { throw Failure.invalidFrame }
        return try AES.GCM.seal(jpeg, using: key, authenticating: self.sequence(sequence)).combined!
    }
    public static func open(_ frame: Data, key: SymmetricKey, sequence: UInt64) throws -> Data {
        guard (29...maximumFrameBytes).contains(frame.count) else { throw Failure.invalidFrame }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: frame), using: key, authenticating: self.sequence(sequence))
    }
    public static func header(length: Int) -> Data {
        withUnsafeBytes(of: UInt32(length).bigEndian) { Data($0) }
    }
    public static func frameLength(_ header: Data) throws -> Int {
        guard header.count == 4 else { throw Failure.invalidFrame }
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        guard (29...maximumFrameBytes).contains(length) else { throw Failure.invalidFrame }
        return length
    }
    public enum Failure: Error { case invalidFrame, authentication }
}
