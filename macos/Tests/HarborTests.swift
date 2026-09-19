import CryptoKit
import Foundation
import AppKit
import Darwin
import SwiftTerm
import SwiftUI
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

    #if DEBUG
    @MainActor
    func testRedesignedScreenshots() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".work/ui-capture-enabled").path) else { throw XCTSkip("Visual fixture capture is opt-in.") }
        let directory = workspace.appendingPathComponent(".work/ui-vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        try vault.save(library)
        let store = LibraryStore(testVault: vault, library: library)
        let sharing = SharingService(store: store)
        store.onLock = { [weak sharing] in sharing?.stop() }
        defer { store.lock() }

        let main = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1000, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        main.isReleasedWhenClosed = false
        main.contentView = NSHostingView(rootView: ContentView(store: store, sharing: sharing).preferredColorScheme(.dark))
        main.makeKeyAndOrderFront(nil)
        defer { main.close() }
        try await Task.sleep(nanoseconds: 350_000_000)
        try capture(main, to: workspace.appendingPathComponent(".work/mac-1.1-empty.png"))

        let editor = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 560, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        editor.isReleasedWhenClosed = false
        editor.contentView = NSHostingView(rootView: HostEditor(host: Host(), store: store).preferredColorScheme(.dark))
        editor.makeKeyAndOrderFront(nil)
        defer { editor.close() }
        try await Task.sleep(nanoseconds: 350_000_000)
        try capture(editor, to: workspace.appendingPathComponent(".work/mac-1.1-editor.png"))
        editor.orderOut(nil)

        let host = Host(name: "Web server", address: "192.168.1.42", username: "deploy", secret: "fixture-password")
        try store.save(host)
        main.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 350_000_000)
        try capture(main, to: workspace.appendingPathComponent(".work/mac-1.1-host.png"))

        let pair = NSWindow(contentRect: NSRect(x: 90, y: 90, width: 720, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        pair.isReleasedWhenClosed = false
        pair.contentView = NSHostingView(rootView: SharingView(store: store, sharing: sharing).preferredColorScheme(.dark))
        pair.makeKeyAndOrderFront(nil)
        defer { pair.close() }
        sharing.port = String(Int.random(in: 30000...60000))
        sharing.inviteAutomatically()
        XCTAssertNotNil(sharing.invitation, sharing.error ?? "No invitation")
        try await Task.sleep(nanoseconds: 350_000_000)
        try capture(pair, to: workspace.appendingPathComponent(".work/mac-1.1-pairing.png"))
    }

    @MainActor
    private func capture(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView else { throw HarborError.message("No view to capture.") }
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw HarborError.message("Could not render the test window.") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw HarborError.message("Could not encode the screenshot.") }
        try png.write(to: url, options: .atomic)
    }

    @MainActor
    func testLoopbackPairingRetrySyncDeletionAndRevocation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        let host = Host(name: "Loopback", address: "127.0.0.1", username: "tester", secret: "fixture-credential")
        library.hosts = [host]
        try vault.save(library)
        let store = LibraryStore(testVault: vault, library: library)
        let sharing = SharingService(store: store)
        store.onLock = { [weak sharing] in sharing?.stop() }
        defer { store.lock() }
        sharing.address = "127.0.0.1"
        sharing.port = String(Int.random(in: 30000...60000))
        sharing.start()
        XCTAssertTrue(sharing.enabled, sharing.error ?? "")
        sharing.invite()
        let first = try XCTUnwrap(sharing.invitation)
        let secret = try XCTUnwrap(Data(base64Encoded: first.secret))
        let deviceID = UUID().uuidString.lowercased()
        let nonce = Data(repeating: 7, count: 32).base64EncodedString()
        let request = try SyncCrypto.seal(PairRequest(deviceId: deviceID, deviceName: "Test phone", clientNonce: nonce), key: secret, aad: "harbor/pair-request/v1/\(first.pairId)")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let firstPath = "/v1/pair/\(first.pairId)"
        let pending = try await post(session, port: sharing.port, path: firstPath, body: JSONEncoder().encode(request))
        XCTAssertEqual(pending.status, 202)
        XCTAssertEqual(sharing.pending?.id, deviceID)
        sharing.approve()
        XCTAssertNil(sharing.error)
        let approved = try await post(session, port: sharing.port, path: firstPath, body: JSONEncoder().encode(request))
        XCTAssertEqual(approved.status, 200)
        let original = try JSONDecoder().decode(Envelope.self, from: approved.body)
        let paired = try SyncCrypto.open(PairResponse.self, envelope: original, key: secret, aad: "harbor/pair-response/v1/\(first.pairId)")
        XCTAssertEqual(paired.deviceId, deviceID)
        XCTAssertEqual(paired.vaultId, library.desktopID)
        sharing.invite()
        XCTAssertNotEqual(sharing.invitation?.pairId, first.pairId)
        let retried = try await post(session, port: sharing.port, path: firstPath, body: JSONEncoder().encode(request))
        XCTAssertEqual(retried.status, 200)
        let cached = try JSONDecoder().decode(Envelope.self, from: retried.body)
        XCTAssertEqual(cached.nonce, original.nonce)
        XCTAssertEqual(cached.ciphertext, original.ciphertext)
        XCTAssertEqual(cached.tag, original.tag)
        let wrong = try SyncCrypto.seal(PairRequest(deviceId: UUID().uuidString.lowercased(), deviceName: "Other", clientNonce: nonce), key: secret, aad: "harbor/pair-request/v1/\(first.pairId)")
        let rejected = try await post(session, port: sharing.port, path: firstPath, body: JSONEncoder().encode(wrong))
        XCTAssertEqual(rejected.status, 403)
        let syncKey = try XCTUnwrap(Data(base64Encoded: paired.syncKey))
        let snapshot = try await sync(session, port: sharing.port, store: store, deviceID: deviceID, key: syncKey)
        XCTAssertEqual(snapshot.hosts.count, 1)
        XCTAssertEqual(snapshot.hosts.first?.password, host.secret)
        XCTAssertEqual(snapshot.vaultId, library.desktopID)
        store.delete(host)
        XCTAssertNil(store.error)
        let deleted = try await sync(session, port: sharing.port, store: store, deviceID: deviceID, key: syncKey)
        XCTAssertTrue(deleted.hosts.isEmpty)
        XCTAssertGreaterThan(deleted.revision, snapshot.revision)
        sharing.revoke(try XCTUnwrap(store.library.devices.first))
        let syncRequest = try makeSyncRequest(vaultID: library.desktopID, deviceID: deviceID, key: syncKey)
        let revoked = try await post(session, port: sharing.port, path: "/v1/sync", body: JSONEncoder().encode(syncRequest))
        XCTAssertEqual(revoked.status, 403)
        store.lock()
        XCTAssertFalse(sharing.enabled)
        XCTAssertFalse(store.loaded)
    }

    @MainActor
    func testDisposableServerThroughNativeTerminal() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = workspace.appendingPathComponent(".work/ssh-fixture-hosts.json")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else { throw XCTSkip("Disposable SSH fixture is unavailable.") }
        let fixtures = try JSONDecoder().decode([WireHost].self, from: Data(contentsOf: fixtureURL))
        XCTAssertEqual(fixtures.count, 3)
        let root = workspace.appendingPathComponent(".work/ssh-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let port = 48605
        for (index, fixture) in fixtures.enumerated() {
            var host = Host(name: fixture.name, address: "127.0.0.1", port: port, username: fixture.username)
            host.auth = fixture.authType == "password" ? .password : .key
            host.secret = host.auth == .password ? fixture.password : fixture.passphrase
            host.privateKey = fixture.privateKey
            host.knownHosts = "[127.0.0.1]:\(port) \(fixture.hostKey)\n"
            if index == 0 {
                let scan = try await SSH.inspect(host)
                XCTAssertTrue(scan.records.contains(fixture.hostKey))
            }
            let session = try TerminalSession(host: host, root: root)
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 800, height: 500), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            var closed = false
            defer { if !closed { session.close(); window.close() } }
            window.contentView = session.terminal
            window.makeKeyAndOrderFront(nil)
            let ready = await waitForTerminal(session, text: "harbor-fixture $", seconds: 15)
            guard ready else {
                let output = String(data: session.terminal.getTerminal().getBufferAsData(kind: .normal), encoding: .utf8) ?? ""
                XCTFail("SSH shell did not reach its prompt for \(fixture.name); status \(session.status), denied \(output.contains("Permission denied")), host key failure \(output.contains("Host key verification failed")), askpass failure \(output.contains("askpass"))")
                return
            }
            let marker = "HARBOR_QA_\(index)_DONE"
            let command = Array("printf 'HARBOR_QA_%s_DONE\\n' '\(index)'\r".utf8)
            session.terminal.send(data: command[...])
            let executed = await waitForTerminal(session, text: marker, seconds: 8)
            XCTAssertTrue(executed, "SSH shell did not execute the command for \(fixture.name).")
            if index == 1 {
                let bounds = session.terminal.bounds
                session.terminal.displayIfNeeded()
                if let bitmap = session.terminal.bitmapImageRepForCachingDisplay(in: bounds) {
                    session.terminal.cacheDisplay(in: bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try png.write(to: workspace.appendingPathComponent(".work/mac-terminal.png"), options: .atomic)
                    }
                }
            }
            if index == 0 {
                let columns = session.terminal.getTerminal().cols
                window.setContentSize(NSSize(width: 1100, height: 650))
                var resized = false
                for _ in 0..<30 {
                    if session.terminal.getTerminal().cols > columns { resized = true; break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                XCTAssertTrue(resized, "The terminal did not resize with its window.")
                if resized {
                    let dimensions = session.terminal.getTerminal().getDims()
                    let sizeCommand = Array("printf 'HARBOR_QA_SIZE_%s_DONE\\n' \"$(stty size)\"\r".utf8)
                    session.terminal.send(data: sizeCommand[...])
                    let remoteSize = await waitForTerminal(session, text: "HARBOR_QA_SIZE_\(dimensions.rows) \(dimensions.cols)_DONE", seconds: 8)
                    XCTAssertTrue(remoteSize, "The remote PTY did not receive the terminal resize.")
                }
            }
            session.close()
            window.close()
            closed = true
            let sessions = root.appendingPathComponent("Sessions")
            XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: sessions.path)).isEmpty)
        }
        let changed = fixtures[1]
        var wrong = Host(name: changed.name, address: "127.0.0.1", port: port, username: changed.username)
        wrong.auth = .key
        wrong.privateKey = changed.privateKey
        let parts = changed.hostKey.split(separator: " ")
        var key = try XCTUnwrap(Data(base64Encoded: String(try XCTUnwrap(parts.last))))
        key[key.count - 1] ^= 1
        wrong.knownHosts = "[127.0.0.1]:\(port) \(parts[0]) \(key.base64EncodedString())\n"
        let rejected = try TerminalSession(host: wrong, root: root)
        defer { rejected.close() }
        let refused = await waitForTerminal(rejected, text: "Host key verification failed", seconds: 8)
        XCTAssertTrue(refused, "OpenSSH did not report the changed server key.")
        XCTAssertFalse(String(data: rejected.terminal.getTerminal().getBufferAsData(kind: .normal), encoding: .utf8)?.contains("harbor-fixture $") ?? false)
    }

    @MainActor
    func testAndroidInteropAgainstLiveMacSharing() async throws {
        struct Configuration: Decodable { let address: String; let port: Int }
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let work = workspace.appendingPathComponent(".work")
        let configURL = work.appendingPathComponent("dart-interop-config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else { throw XCTSkip("Android interop fixture is unavailable.") }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
        let fixtures = try JSONDecoder().decode([WireHost].self, from: Data(contentsOf: work.appendingPathComponent("ssh-fixture-hosts.json")))
        let key = try XCTUnwrap(fixtures.first?.hostKey)
        let directory = work.appendingPathComponent("dart-interop-vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        var host = Host(name: "Android interop", address: "127.0.0.1", port: 48605, username: "harbor", secret: "fixture-credential")
        host.knownHosts = "[127.0.0.1]:48605 \(key)\n"
        library.hosts = [host]
        try vault.save(library)
        let store = LibraryStore(testVault: vault, library: library)
        let sharing = SharingService(store: store)
        store.onLock = { [weak sharing] in sharing?.stop() }
        defer { store.lock() }
        sharing.address = config.address
        sharing.port = String(config.port)
        sharing.start()
        guard sharing.enabled else { XCTFail(sharing.error ?? "Sharing did not start."); return }
        sharing.invite()
        let invitation = try XCTUnwrap(sharing.invitation)
        let invitationURL = work.appendingPathComponent("dart-interop-invitation.json")
        let doneURL = work.appendingPathComponent("dart-interop-done")
        try? FileManager.default.removeItem(at: invitationURL)
        try? FileManager.default.removeItem(at: doneURL)
        defer { try? FileManager.default.removeItem(at: invitationURL) }
        let descriptor = open(invitationURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw HarborError.message("Could not create the private Android invitation fixture.") }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try file.write(contentsOf: JSONEncoder().encode(invitation))
        try file.close()
        for _ in 0..<900 {
            if sharing.pending != nil, !sharing.approvedPairing { sharing.approve() }
            if let error = sharing.error { XCTFail(error); return }
            if FileManager.default.fileExists(atPath: doneURL.path) {
                XCTAssertEqual(store.library.devices.count, 1)
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Android did not complete pairing and two syncs before the interop deadline.")
    }

    @MainActor
    private func waitForTerminal(_ session: TerminalSession, text: String, seconds: Int) async -> Bool {
        for _ in 0..<(seconds * 10) {
            if String(data: session.terminal.getTerminal().getBufferAsData(kind: .normal), encoding: .utf8)?.contains(text) == true { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private func makeSyncRequest(vaultID: String, deviceID: String, key: Data) throws -> Envelope {
        let nonce = SyncCrypto.random(32).base64EncodedString()
        var envelope = try SyncCrypto.seal(SyncRequest(version: 1, vaultId: vaultID, requestId: nonce), key: key, aad: "harbor/sync-request/v1/\(deviceID)")
        envelope.deviceId = deviceID
        return envelope
    }

    @MainActor
    private func sync(_ session: URLSession, port: String, store: LibraryStore, deviceID: String, key: Data) async throws -> Snapshot {
        let request = try makeSyncRequest(vaultID: store.library.desktopID, deviceID: deviceID, key: key)
        let response = try await post(session, port: port, path: "/v1/sync", body: JSONEncoder().encode(request))
        XCTAssertEqual(response.status, 200)
        let sealed = try JSONDecoder().decode(Envelope.self, from: response.body)
        let signed = try SyncCrypto.open(SignedSnapshot.self, envelope: sealed, key: key, aad: "harbor/sync-response/v1/\(deviceID)")
        let publicKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: store.library.signingKey)!).publicKey
        XCTAssertTrue(publicKey.isValidSignature(Data(base64Encoded: signed.signature)!, for: Data("harbor.snapshot.v1\n\(signed.payload)".utf8)))
        return try JSONDecoder().decode(Snapshot.self, from: Data(base64Encoded: signed.payload)!)
    }

    private func post(_ session: URLSession, port: String, path: String, body: Data) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 5
        for attempt in 0..<20 {
            do {
                let (data, response) = try await session.data(for: request)
                return ((response as! HTTPURLResponse).statusCode, data)
            } catch {
                if attempt == 19 { throw error }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        throw HarborError.message("The test listener did not start.")
    }
    #endif

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
        XCTAssertTrue(SharingService.isPrivateAddress("100.64.0.0"))
        XCTAssertTrue(SharingService.isPrivateAddress("100.127.255.255"))
        XCTAssertTrue(SharingService.isPrivateAddress("fd00::1"))
        XCTAssertFalse(SharingService.isPrivateAddress("8.8.8.8"))
        XCTAssertFalse(SharingService.isPrivateAddress("100.63.255.255"))
        XCTAssertFalse(SharingService.isPrivateAddress("100.128.0.0"))
        XCTAssertFalse(SharingService.isPrivateAddress("172.32.0.1"))
        XCTAssertFalse(SharingService.isPrivateAddress("desktop.local"))
    }

    @MainActor
    func testAutomaticPairingNetworkChoicesAvoidLoopbackAndBridges() {
        XCTAssertNil(PairingNetwork.candidate(interface: "lo0", address: "127.0.0.1"))
        XCTAssertNil(PairingNetwork.candidate(interface: "bridge100", address: "192.168.64.1"))
        XCTAssertNil(PairingNetwork.candidate(interface: "awdl0", address: "169.254.1.2"))
        XCTAssertNil(PairingNetwork.candidate(interface: "en0", address: "8.8.8.8"))
        XCTAssertNil(PairingNetwork.candidate(interface: "en0", address: "fe80::1"))
        XCTAssertEqual(PairingNetwork.candidate(interface: "en0", address: "192.168.1.5")?.priority, 0)
        XCTAssertEqual(PairingNetwork.candidate(interface: "utun4", address: "100.64.207.29")?.priority, 1)
        XCTAssertEqual(PairingNetwork.candidate(interface: "en0", address: "fd00::5")?.priority, 2)
        XCTAssertEqual(PairingNetwork.candidate(interface: "utun4", address: "100.64.207.29")?.name, "Private VPN (utun4)")
    }

    @MainActor
    func testHostEditorDefaultsNameOnlyAtSaveAndPreservesKeyDraft() throws {
        var host = Host(address: "example.com", username: "deploy")
        XCTAssertEqual(host.name, "")
        let saved = try HostEditor.preparedHost(host, portText: "22", password: "fixture-secret", passphrase: "")
        XCTAssertEqual(saved.name, "example.com")
        XCTAssertEqual(saved.secret, "fixture-secret")
        host.auth = .key
        host.privateKey = "-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----"
        let key = try HostEditor.preparedHost(host, portText: "2222", password: "unused", passphrase: "fixture-passphrase")
        XCTAssertEqual(key.privateKey, host.privateKey)
        XCTAssertEqual(key.secret, "fixture-passphrase")
        XCTAssertEqual(key.port, 2222)
        XCTAssertThrowsError(try HostEditor.preparedHost(host, portText: "0", password: "", passphrase: ""))
    }
}
