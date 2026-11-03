import Foundation

public struct Pointer: Equatable, Sendable {
    public private(set) var x: Double
    public private(set) var y: Double
    public init(x: Double = 0.5, y: Double = 0.5) {
        self.x = Self.clamp(x)
        self.y = Self.clamp(y)
    }
    public mutating func move(dx: Double, dy: Double, width: Double, height: Double) {
        guard width > 0, height > 0 else { return }
        x = Self.clamp(x + dx / width)
        y = Self.clamp(y + dy / height)
    }
    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0.5
    }
    /// Report ID belongs in GATT's Report Reference descriptor, not in this payload.
    public var absoluteReport: [UInt8] {
        let px = UInt16((x * 32767).rounded())
        let py = UInt16((y * 32767).rounded())
        return [0, UInt8(px & 255), UInt8(px >> 8), UInt8(py & 255), UInt8(py >> 8)]
    }
}

public enum CursorReport {
    public static let keyboardID: UInt8 = 1
    public static let absoluteID: UInt8 = 2
    public static let mouseID: UInt8 = 3
    public static func mouse(down: Bool, wheel: Int = 0, dx: Int = 0, dy: Int = 0) -> [UInt8] {
        [down ? 1 : 0, UInt8(bitPattern: Int8(clamping: dx)),
         UInt8(bitPattern: Int8(clamping: dy)), UInt8(bitPattern: Int8(clamping: wheel))]
    }
    // Standard HID mouse collections; adapted from iPhone Use (MIT), see THIRD_PARTY_NOTICES.
    public static let descriptor: [UInt8] = mouseDescriptor + keyboardDescriptor
    private static let keyboardDescriptor: [UInt8] = [
        0x05,0x01,0x09,0x06,0xA1,0x01,0x85,0x01,
        0x05,0x07,0x19,0xE0,0x29,0xE7,0x15,0x00,0x25,0x01,
        0x75,0x01,0x95,0x08,0x81,0x02,
        0x95,0x01,0x75,0x08,0x81,0x01,
        0x95,0x06,0x75,0x08,0x15,0x00,0x25,0x65,
        0x05,0x07,0x19,0x00,0x29,0x65,0x81,0x00,0xC0
    ]
    public static func length(for id: UInt8) -> Int {
        switch id { case keyboardID: 8; case absoluteID: 5; case mouseID: 4; default: 0 }
    }
    private static let mouseDescriptor: [UInt8] = [
        0x05,0x01,0x09,0x02,0xA1,0x01,0x85,0x02,0x09,0x01,0xA1,0x00,
        0x05,0x09,0x19,0x01,0x29,0x03,0x15,0x00,0x25,0x01,
        0x95,0x03,0x75,0x01,0x81,0x02,0x95,0x01,0x75,0x05,0x81,0x01,
        0x05,0x01,0x09,0x30,0x09,0x31,0x16,0x00,0x00,0x26,0xFF,0x7F,
        0x75,0x10,0x95,0x02,0x81,0x02,0xC0,0xC0,
        0x05,0x01,0x09,0x02,0xA1,0x01,0x85,0x03,0x09,0x01,0xA1,0x00,
        0x05,0x09,0x19,0x01,0x29,0x03,0x15,0x00,0x25,0x01,
        0x95,0x03,0x75,0x01,0x81,0x02,0x95,0x01,0x75,0x05,0x81,0x01,
        0x05,0x01,0x09,0x30,0x09,0x31,0x09,0x38,0x15,0x81,0x25,0x7F,
        0x75,0x08,0x95,0x03,0x81,0x06,0xC0,0xC0
    ]
}

/// Bounded queue: coalesce consecutive positions, preserve button order, fail closed on overflow.
public struct ReportQueue {
    public struct Item: Equatable {
        public let id: UInt8
        public let bytes: [UInt8]
    }
    public private(set) var items: [Item] = []
    public let capacity: Int
    public init(capacity: Int = 128) { self.capacity = max(2, capacity) }
    @discardableResult public mutating func append(id: UInt8, bytes: [UInt8]) -> Bool {
        if id == CursorReport.absoluteID, items.last?.id == id {
            items[items.count - 1] = Item(id: id, bytes: bytes)
            return true
        }
        guard items.count < capacity else {
            // Never deliver a delayed click after the user has lost control.
            release()
            return false
        }
        items.append(Item(id: id, bytes: bytes))
        return true
    }
    public mutating func pop() { if !items.isEmpty { items.removeFirst() } }
    public mutating func release() {
        items = [Item(id: CursorReport.mouseID, bytes: CursorReport.mouse(down: false)),
                 Item(id: CursorReport.keyboardID, bytes: Array(repeating: 0, count: 8))]
    }
    public mutating func clear() { items.removeAll() }
}
