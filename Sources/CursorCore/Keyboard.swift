import Foundation

/// Standard 8-byte HID keyboard state, with six simultaneous non-modifier keys.
/// Mac virtual key codes describe physical positions; the iPhone's layout determines text.
public struct KeyboardState {
    public private(set) var modifiers: UInt8 = 0
    private var keys: [UInt8] = []
    public init() {}
    public var report: [UInt8] { [modifiers, 0] + keys + Array(repeating: 0, count: 6 - keys.count) }
    public mutating func setModifiers(_ value: UInt8) { modifiers = value }
    @discardableResult public mutating func press(macKeyCode: UInt16) -> Bool {
        guard let usage = Self.usage(for: macKeyCode) else { return false }
        if !keys.contains(usage), keys.count < 6 { keys.append(usage) }
        return true
    }
    public mutating func release(macKeyCode: UInt16) {
        if let usage = Self.usage(for: macKeyCode) { keys.removeAll { $0 == usage } }
    }
    public mutating func releaseAll() { keys.removeAll(); modifiers = 0 }
    public static func usage(for code: UInt16) -> UInt8? { map[code] }
    private static let map: [UInt16: UInt8] = [
        0:4,1:22,2:7,3:9,4:11,5:10,6:29,7:27,8:6,9:25,11:5,
        12:20,13:26,14:8,15:21,16:28,17:23,
        18:30,19:31,20:32,21:33,22:35,23:34,24:46,25:38,26:36,27:45,
        28:37,29:39,30:48,31:18,32:24,33:47,34:12,35:19,36:40,
        37:15,38:13,39:52,40:14,41:51,42:49,43:54,44:56,45:17,
        46:16,47:55,48:43,49:44,50:53,51:42,53:41,57:57,
        65:99,67:85,69:87,71:83,75:84,76:88,78:86,81:103,
        82:98,83:89,84:90,85:91,86:92,87:93,88:94,89:95,91:96,92:97,
        96:62,97:63,98:64,99:60,100:65,101:66,103:68,105:104,
        106:107,107:105,109:67,111:69,113:106,114:73,115:74,
        116:75,117:76,118:61,119:77,120:59,121:78,122:58,
        123:80,124:79,125:81,126:82
    ]
}
