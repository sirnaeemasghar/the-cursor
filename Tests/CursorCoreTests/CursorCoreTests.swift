import XCTest
@testable import CursorCore

final class CursorCoreTests: XCTestCase {
    func testCoordinateMappingAndClamping() {
        XCTAssertEqual(Pointer(x: 0, y: 1).absoluteReport, [0,0,0,255,127])
        XCTAssertEqual(Pointer(x: 1, y: 0).absoluteReport, [0,255,127,0,0])
        var p = Pointer(x: 0.5, y: 0.5)
        p.move(dx: 300, dy: -900, width: 300, height: 600)
        XCTAssertEqual(p, Pointer(x: 1, y: 0))
        p.move(dx: 10, dy: 10, width: 0, height: 0)
        XCTAssertEqual(p, Pointer(x: 1, y: 0))
        XCTAssertEqual(Pointer(x: .nan, y: .infinity), Pointer())
    }
    func testMouseReportClampsScrollAndPreservesButtons() {
        XCTAssertEqual(CursorReport.mouse(down: true, wheel: 999), [1,0,0,127])
        XCTAssertEqual(CursorReport.mouse(down: false, wheel: -999), [0,0,0,128])
    }
    func testRelativeDragPlansReachTargetsWithinEstimatedTolerance() {
        let paths: [(Pointer, Pointer)] = [
            (Pointer(x: 0.8, y: 0.5), Pointer(x: 0.2, y: 0.5)),
            (Pointer(x: 0.2, y: 0.5), Pointer(x: 0.8, y: 0.5)),
            (Pointer(x: 0.5, y: 1), Pointer(x: 0.5, y: 0.2)),
            (Pointer(x: 0.9, y: 0), Pointer(x: 0.9, y: 0.7))
        ]
        for (start, end) in paths {
            var drag = RelativeDrag(start: start, aspectRatio: 393.0 / 852.0)
            let deltas = drag.move(to: end)
            XCTAssertFalse(deltas.isEmpty)
            XCTAssertLessThanOrEqual(deltas.count, 64)
            XCTAssertTrue(deltas.allSatisfy { abs($0.x) <= 32 && abs($0.y) <= 32 && ($0.x == 0 || $0.y == 0) })
            XCTAssertEqual(drag.estimatedPointer.x, end.x, accuracy: 0.001)
            XCTAssertEqual(drag.estimatedPointer.y, end.y, accuracy: 0.001)
            XCTAssertTrue(drag.move(to: end).isEmpty)
        }
    }
    func testRelativeMouseReportsCarryMotionAndHeldButtonTogether() {
        XCTAssertEqual(CursorReport.mouse(down: true, dx: -32, dy: 12), [1,224,12,0])
        XCTAssertEqual(CursorReport.mouse(down: false, dx: 999, dy: -999), [0,127,128,0])
    }
    func testCoalescingNeverCrossesButtonTransitions() {
        var q = ReportQueue()
        q.append(id: 2, bytes: [1]); q.append(id: 2, bytes: [2])
        q.append(id: 3, bytes: CursorReport.mouse(down: true))
        q.append(id: 2, bytes: [3]); q.append(id: 2, bytes: [4])
        q.append(id: 3, bytes: CursorReport.mouse(down: false))
        XCTAssertEqual(q.items.map(\.bytes), [[2],[1,0,0,0],[4],[0,0,0,0]])
        q.release()
        XCTAssertEqual(q.items.count, 2)
        XCTAssertEqual(q.items.first?.bytes, [0,0,0,0])
        XCTAssertEqual(q.items.last?.id, CursorReport.keyboardID)
        XCTAssertEqual(q.items.last?.bytes, Array(repeating: 0, count: 8))
    }
    func testOverflowDiscardsDelayedClicksAndReleases() {
        var q = ReportQueue(capacity: 2)
        q.append(id: 3, bytes: CursorReport.mouse(down: true))
        q.append(id: 3, bytes: CursorReport.mouse(down: false))
        XCTAssertFalse(q.append(id: 3, bytes: CursorReport.mouse(down: true)))
        XCTAssertEqual(q.items.count, 2)
        XCTAssertEqual(q.items.first?.bytes, CursorReport.mouse(down: false))
        XCTAssertEqual(q.items.last?.bytes, Array(repeating: 0, count: 8))
    }
    func testKeyboardPressModifiersAndRelease() {
        var keyboard = KeyboardState()
        keyboard.setModifiers(2)
        XCTAssertTrue(keyboard.press(macKeyCode: 0)) // Shift+A
        XCTAssertEqual(keyboard.report, [2,0,4,0,0,0,0,0])
        keyboard.press(macKeyCode: 0) // Repeated keydown never duplicates a held key.
        XCTAssertEqual(keyboard.report, [2,0,4,0,0,0,0,0])
        keyboard.release(macKeyCode: 0)
        XCTAssertEqual(keyboard.report, [2,0,0,0,0,0,0,0])
        keyboard.releaseAll()
        XCTAssertEqual(keyboard.report, Array(repeating: 0, count: 8))
    }
    func testKeyboardRolloverAndEditingKeys() {
        var keyboard = KeyboardState()
        for key: UInt16 in [0,1,2,3,4,5,6] { keyboard.press(macKeyCode: key) }
        XCTAssertEqual(keyboard.report.count, 8)
        XCTAssertEqual(keyboard.report.dropFirst(2).filter { $0 != 0 }.count, 6)
        keyboard.releaseAll()
        XCTAssertFalse(keyboard.press(macKeyCode: 65535))
        XCTAssertEqual(KeyboardState.usage(for: 51), 42) // Delete/backspace
        XCTAssertEqual(KeyboardState.usage(for: 36), 40) // Return
        XCTAssertEqual(KeyboardState.usage(for: 123), 80) // Left arrow edits text.
        XCTAssertEqual(CursorReport.length(for: CursorReport.keyboardID), 8)
    }
    func testPairingRejectsUnsupportedAndMalformedCodes() throws {
        let code = PairingCode()
        XCTAssertEqual(try PairingCode.parse(code.json), code)
        XCTAssertThrowsError(try PairingCode.parse("https://example.com"))
        XCTAssertThrowsError(try PairingCode.parse(code.json.replacingOccurrences(of: code.token, with: "invalid")))
        XCTAssertThrowsError(try PairingCode.parse(code.json.replacingOccurrences(of: PairingProtocol.service, with: "wrong")))
    }
    func testScreenHandshakeRequiresSessionAndValidDimensions() throws {
        let code = PairingCode()
        try PhoneHello(token: code.token, name: "iPhone", width: 393, height: 852).validate(token: code.token)
        XCTAssertThrowsError(try PhoneHello(token: "wrong", name: "iPhone", width: 393, height: 852).validate(token: code.token))
        XCTAssertThrowsError(try PhoneHello(token: code.token, name: "iPhone", width: 0, height: 852).validate(token: code.token))
        XCTAssertThrowsError(try PhoneHello(token: code.token, name: "iPhone", width: 5000, height: 100).validate(token: code.token))
    }
}
