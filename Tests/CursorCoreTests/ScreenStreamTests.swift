import XCTest
@testable import CursorCore

final class ScreenStreamTests: XCTestCase {
    func testMutualAuthenticationAndFreshSessionKeys() throws {
        let key = ScreenStreamProtocol.key(token: "paired-secret")
        let wrong = ScreenStreamProtocol.key(token: "another-mac")
        let server = ScreenStreamProtocol.nonce(), client = ScreenStreamProtocol.nonce()
        let challenge = ScreenStreamProtocol.challenge(nonce: server, key: key)
        XCTAssertTrue(ScreenStreamProtocol.verify(challenge, key: key))
        XCTAssertFalse(ScreenStreamProtocol.verify(challenge, key: wrong))
        XCTAssertFalse(ScreenStreamProtocol.verify(challenge, prior: server, key: key))
        let response = ScreenStreamProtocol.challenge(nonce: client, prior: server, key: key)
        XCTAssertTrue(ScreenStreamProtocol.verify(response, prior: server, key: key))
        XCTAssertFalse(ScreenStreamProtocol.verify(response, prior: ScreenStreamProtocol.nonce(), key: key))
        let session = ScreenStreamProtocol.sessionKey(key: key, server: server, client: client)
        let next = ScreenStreamProtocol.sessionKey(key: key, server: server, client: ScreenStreamProtocol.nonce())
        let frame = try ScreenStreamProtocol.seal(Data([1,2,3]), key: session, sequence: 0)
        XCTAssertThrowsError(try ScreenStreamProtocol.open(frame, key: next, sequence: 0))
    }
    func testFrameTamperingAndReplayAreRejected() throws {
        let key = ScreenStreamProtocol.key(token: "paired-secret")
        let jpeg = Data(repeating: 42, count: 100)
        let frame = try ScreenStreamProtocol.seal(jpeg, key: key, sequence: 5)
        XCTAssertEqual(try ScreenStreamProtocol.open(frame, key: key, sequence: 5), jpeg)
        XCTAssertThrowsError(try ScreenStreamProtocol.open(frame, key: key, sequence: 6))
        var changed = frame; changed[changed.count - 1] ^= 1
        XCTAssertThrowsError(try ScreenStreamProtocol.open(changed, key: key, sequence: 5))
        XCTAssertThrowsError(try ScreenStreamProtocol.open(frame, key: ScreenStreamProtocol.key(token: "wrong"), sequence: 5))
    }
    func testUntrustedFrameLengthIsBoundedBeforeAllocation() throws {
        for length in [29, 4096, ScreenStreamProtocol.maximumFrameBytes] {
            XCTAssertEqual(try ScreenStreamProtocol.frameLength(ScreenStreamProtocol.header(length: length)), length)
        }
        for length in [0, 28, ScreenStreamProtocol.maximumFrameBytes + 1, Int(UInt32.max)] {
            XCTAssertThrowsError(try ScreenStreamProtocol.frameLength(ScreenStreamProtocol.header(length: length)))
        }
        XCTAssertThrowsError(try ScreenStreamProtocol.frameLength(Data([1,2,3])))
        XCTAssertThrowsError(try ScreenStreamProtocol.seal(Data(), key: ScreenStreamProtocol.key(token: "test"), sequence: 0))
    }
}
