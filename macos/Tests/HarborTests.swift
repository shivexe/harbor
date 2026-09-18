import CryptoKit
import Foundation
import AppKit
import SwiftTerm
import XCTest
@testable import Harbor

final class HarborTests: XCTestCase {
    struct Payload: Codable, Equatable { let value: String }

    func testSharedProtocolVectors() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "protocol-vectors", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let secret = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["secret"] as? String)))
        let nonce = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["clientNonce"] as? String)))
        XCTAssertEqual(SyncCrypto.comparison(secret: secret, nonce: nonce), fixture["comparisonCode"] as? String)
        let vectors = try XCTUnwrap(fixture["messages"] as? [[String: Any]])
        for vector in vectors {
            switch vector["name"] as? String {
            case "pairRequest": try verify(PairRequest.self, vector: vector)
            case "pairResponse": try verify(PairResponse.self, vector: vector)
            case "syncRequest": try verify(SyncRequest.self, vector: vector)
            case "syncResponse": try verify(SignedSnapshot.self, vector: vector)
            default: XCTFail("Unknown protocol vector")
            }
        }
        let publicBytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["publicKey"] as? String)))
        let signature = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture["signature"] as? String)))
        let payload = try XCTUnwrap(fixture["payload"] as? String)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
        XCTAssertTrue(publicKey.isValidSignature(signature, for: Data("harbor.snapshot.v1\n\(payload)".utf8)))
        XCTAssertFalse(publicKey.isValidSignature(signature, for: Data("harbor.snapshot.v1\n\(payload)x".utf8)))
    }

    private func verify<T: Codable>(_ type: T.Type, vector: [String: Any]) throws {
        let key = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(vector["key"] as? String)))
        let aad = try XCTUnwrap(vector["aad"] as? String)
        let envelopeBytes = try JSONSerialization.data(withJSONObject: try XCTUnwrap(vector["envelope"] as? [String: Any]))
        let envelope = try JSONDecoder().decode(Envelope.self, from: envelopeBytes)
        let value = try SyncCrypto.open(type, envelope: envelope, key: key, aad: aad)
        let actual = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary
        let expected = try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(vector["plaintext"] as? String).utf8)) as? NSDictionary
        XCTAssertEqual(actual, expected)
        XCTAssertThrowsError(try SyncCrypto.open(type, envelope: envelope, key: key, aad: aad + "/wrong"))
    }

    func testApprovedReplyCachePreservesBindingAcrossNewInvitations() throws {
        var cache = ApprovedReplyCache()
        let envelope = Envelope(nonce: "fixture", ciphertext: "fixture", tag: "fixture")
        let reply = ApprovedPairReply(secret: Data(repeating: 1, count: 32), deviceID: "device-one", nonce: "nonce-one", response: envelope, expiresAt: 400)
        try cache.insert(reply, pairID: "first", now: 100)
        try cache.insert(ApprovedPairReply(secret: Data(repeating: 2, count: 32), deviceID: "device-two", nonce: "nonce-two", response: envelope, expiresAt: 500), pairID: "second", now: 200)
        let saved = try XCTUnwrap(cache.reply(for: "first", now: 300))
        XCTAssertTrue(saved.accepts(PairRequest(deviceId: "device-one", deviceName: "Phone", clientNonce: "nonce-one")))
        XCTAssertFalse(saved.accepts(PairRequest(deviceId: "device-two", deviceName: "Phone", clientNonce: "nonce-one")))
        XCTAssertFalse(saved.accepts(PairRequest(deviceId: "device-one", deviceName: "Phone", clientNonce: "different")))
        XCTAssertEqual(saved.response.ciphertext, envelope.ciphertext)
        XCTAssertNil(cache.reply(for: "first", now: 400))
        cache.purge(at: 400)
        XCTAssertEqual(cache.count, 1)
        cache.revoke("device-two")
        XCTAssertEqual(cache.count, 0)
        for index in 0..<32 { try cache.insert(reply, pairID: String(index), now: 100) }
        XCTAssertThrowsError(try cache.insert(reply, pairID: "overflow", now: 100))
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.nextExpiry)
    }

    func testEncryptedMessageAuthenticatesContext() throws {
        let key = Data(repeating: 7, count: 32)
        let value = Payload(value: "sensitive")
        var envelope = try SyncCrypto.seal(value, key: key, aad: "harbor/sync-request/v1/device")
        XCTAssertEqual(try SyncCrypto.open(Payload.self, envelope: envelope, key: key, aad: "harbor/sync-request/v1/device"), value)
        XCTAssertThrowsError(try SyncCrypto.open(Payload.self, envelope: envelope, key: key, aad: "harbor/sync-response/v1/device"))
        var tag = try XCTUnwrap(Data(base64Encoded: envelope.tag))
        tag[0] ^= 1
        envelope.tag = tag.base64EncodedString()
        XCTAssertThrowsError(try SyncCrypto.open(Payload.self, envelope: envelope, key: key, aad: "harbor/sync-request/v1/device"))
    }

    func testComparisonMatchesSHA256BigEndian() {
        let secret = Data(repeating: 0, count: 32)
        let nonce = Data(repeating: 1, count: 32)
        let digest = Array(SHA256.hash(data: secret + nonce))
        let number = (UInt32(digest[0]) << 24) | (UInt32(digest[1]) << 16) | (UInt32(digest[2]) << 8) | UInt32(digest[3])
        XCTAssertEqual(SyncCrypto.comparison(secret: secret, nonce: nonce), String(format: "%06u", number % 1_000_000))
    }

    func testHostRejectsArgumentAndCredentialInjection() throws {
        var host = Host(name: "Work", address: "192.168.1.2", username: "operator", secret: "secret")
        try host.validate()
        host.address = "-oProxyCommand=touch"
        XCTAssertThrowsError(try host.validate())
        host.address = "192.168.1.2"
        host.secret = "secret\nsecond"
        XCTAssertThrowsError(try host.validate())
        host.secret = "secret"
        host.port = 0
        XCTAssertThrowsError(try host.validate())
    }

    func testVaultDoesNotPersistPlaintextAndRejectsTampering() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        library.hosts = [Host(name: "Work", address: "192.168.1.2", username: "operator", secret: "harbor-test-secret-plain")]
        try vault.save(library)
        var encrypted = try Data(contentsOf: vault.archive)
        XCTAssertNil(encrypted.range(of: Data("harbor-test-secret-plain".utf8)))
        XCTAssertEqual(try vault.load().hosts, library.hosts)
        encrypted[encrypted.count - 1] ^= 1
        try encrypted.write(to: vault.archive)
        XCTAssertThrowsError(try vault.load())
    }

    @MainActor
    func testHTTPFramingRejectsConflictingLengthsAndChunkedUploads() throws {
        let valid = Data("POST /v1/sync HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}".utf8)
        XCTAssertEqual(try HTTPServer.parse(valid)?.path, "/v1/sync")
        XCTAssertNil(try HTTPServer.parse(valid.dropLast()))
        XCTAssertThrowsError(try HTTPServer.parse(Data("POST /v1/sync HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\n{}".utf8)))
        XCTAssertThrowsError(try HTTPServer.parse(Data("POST /v1/sync HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\nTransfer-Encoding: chunked\r\n\r\n{}".utf8)))
        XCTAssertThrowsError(try HTTPServer.parse(valid + Data("extra".utf8)))
    }

    @MainActor
    func testTerminalBridgeRejectsRemoteClipboardReadAndWrite() {
        let terminal = LocalProcessTerminalView(frame: .zero)
        let bridge = TerminalBridge(terminal: terminal)
        let before = NSPasteboard.general.changeCount
        bridge.clipboardCopy(source: terminal, content: Data("remote clipboard".utf8))
        XCTAssertEqual(NSPasteboard.general.changeCount, before)
        XCTAssertNil(bridge.clipboardRead(source: terminal))
    }

    @MainActor
    func testPairingAddressRejectsPublicAndDNSOrigins() {
        XCTAssertTrue(SharingService.isPrivateAddress("192.168.1.3"))
        XCTAssertTrue(SharingService.isPrivateAddress("172.16.0.1"))
        XCTAssertTrue(SharingService.isPrivateAddress("fd00::1"))
        XCTAssertFalse(SharingService.isPrivateAddress("8.8.8.8"))
        XCTAssertFalse(SharingService.isPrivateAddress("172.32.0.1"))
        XCTAssertFalse(SharingService.isPrivateAddress("desktop.local"))
    }
}
