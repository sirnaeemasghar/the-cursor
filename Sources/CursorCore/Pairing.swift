import Foundation
import Security

public enum PairingProtocol {
    public static let service = "BC48C5B0-20C7-4CF3-93D2-A9759DB64201"
    public static let hello = "BC48C5B0-20C7-4CF3-93D2-A9759DB64202"
    public static let command = "BC48C5B0-20C7-4CF3-93D2-A9759DB64203"
    public static let version = 1
}

public struct PairingCode: Codable, Equatable, Sendable {
    public let version: Int
    public let name: String
    public let service: String
    public let token: String
    public init(token: String = UUID().uuidString) {
        version = PairingProtocol.version
        name = "The Cursor"
        service = PairingProtocol.service
        self.token = token
    }
    public var json: String { String(data: try! JSONEncoder().encode(self), encoding: .utf8)! }
    /// Camera-readable app link. Legacy JSON is still accepted by the in-app scanner.
    public var url: URL {
        var parts = URLComponents()
        parts.scheme = "thecursor"; parts.host = "pair"
        parts.queryItems = [URLQueryItem(name: "v", value: String(version)), URLQueryItem(name: "token", value: token)]
        return parts.url!
    }
    public static func parse(_ text: String) throws -> PairingCode {
        guard text.utf8.count <= 2048 else { throw PairingError.invalidCode }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            guard let url = URLComponents(string: text), url.scheme?.lowercased() == "thecursor",
                  url.host?.lowercased() == "pair", url.path.isEmpty || url.path == "/",
                  url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
                  let items = url.queryItems, items.count == 2,
                  items.filter({ $0.name == "v" }).count == 1,
                  items.first(where: { $0.name == "v" })?.value == String(PairingProtocol.version),
                  items.filter({ $0.name == "token" }).count == 1,
                  let token = items.first(where: { $0.name == "token" })?.value,
                  UUID(uuidString: token) != nil else { throw PairingError.invalidCode }
            return PairingCode(token: token)
        }
        let code = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
        guard code.version == PairingProtocol.version,
              code.service == PairingProtocol.service,
              UUID(uuidString: code.token) != nil else { throw PairingError.invalidCode }
        return code
    }
}

public enum PairingError: Error { case invalidCode, invalidScreen }

public struct PhoneHello: Codable, Sendable {
    public let token: String
    public let name: String
    public let width: Double
    public let height: Double
    public init(token: String, name: String, width: Double, height: Double) {
        self.token = token; self.name = name; self.width = width; self.height = height
    }
    public func validate(token expected: String) throws {
        guard token == expected else { throw PairingError.invalidCode }
        guard width.isFinite, height.isFinite,
              (100...5000).contains(width), (100...5000).contains(height),
              (0.2...5).contains(width / height), !name.isEmpty, name.utf8.count <= 128
        else { throw PairingError.invalidScreen }
    }
}

public struct RememberedMac: Codable, Sendable {
    public let code: PairingCode
    public let peripheralID: UUID
    public init(code: PairingCode, peripheralID: UUID) { self.code = code; self.peripheralID = peripheralID }
}

/// Pairing secrets stay in this app's local Keychain, never in logs or source files.
public enum PairingVault {
    public struct Failure: Error { public let status: OSStatus }
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.thecursor.pairing",
         kSecAttrAccount as String: account]
    }
    public static func read<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw Failure(status: status) }
        return try JSONDecoder().decode(type, from: data)
    }
    public static func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        var request = query(account)
        request[kSecValueData as String] = data
        #if os(iOS)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        let status = SecItemAdd(request as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard update == errSecSuccess else { throw Failure(status: update) }
        } else if status != errSecSuccess { throw Failure(status: status) }
    }
    public static func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
