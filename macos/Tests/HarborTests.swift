import CryptoKit
import Foundation
import AppKit
import Darwin
import SwiftTerm
import SwiftUI
import Vision
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

    func testSSHDiagnosticMilestonesRequireOrderedLocalEvidence() {
        var parser = SSHDiagnosticParser()
        parser.consume("Authenticated to example using \"none\".\r\n")
        XCTAssertEqual(parser.phase, .connecting)
        parser.consume("debug2: shell request accepted on channel 0\r\n")
        XCTAssertEqual(parser.phase, .connecting)
        parser.consume("debug1: Connection established.\r\n")
        XCTAssertEqual(parser.phase, .verifying)
        parser.consume("debug1: Host 'example' is known and matches the ED25519 host key.\r\n")
        XCTAssertEqual(parser.phase, .authenticating)
        parser.consume("Authenticated to example using \"none\".\r\n")
        XCTAssertEqual(parser.phase, .openingShell)
        parser.consume("debug1: Entering interactive session.\r\n")
        XCTAssertEqual(parser.phase, .openingShell)
        parser.consume("debug2: shell request accepted on channel 0\r\n")
        XCTAssertEqual(parser.phase, .ready)
        parser.consume("debug1: Host 'example' is known and matches the ED25519 host key.\r\n")
        XCTAssertEqual(parser.phase, .ready)
        var failed = SSHDiagnosticParser()
        failed.consume("Host key verification failed.\r\n")
        XCTAssertNotNil(failed.failureHint)
        XCTAssertEqual(failed.phase, .connecting)
        failed.consume("debug1: Exit status -1\r\n")
        failed.consume("debug1: Exit status unknown\r\n")
        XCTAssertFalse(failed.remoteExitStatus)
        failed.consume("debug1: Exit status 255\r\n")
        XCTAssertTrue(failed.remoteExitStatus)
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

        let main = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 900, height: 600), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        main.isReleasedWhenClosed = false
        main.titleVisibility = .hidden
        main.titlebarAppearsTransparent = true
        main.contentView = NSHostingView(rootView: ContentView(store: store, sharing: sharing).preferredColorScheme(.dark))
        main.makeKeyAndOrderFront(nil)
        defer { main.close() }
        try await Task.sleep(nanoseconds: 350_000_000)
        try capture(main, to: workspace.appendingPathComponent(".work/mac-1.2-empty.png"))

        let editor = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 560, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        editor.isReleasedWhenClosed = false
        editor.contentView = NSHostingView(rootView: HostEditor(host: Host(auth: .none), store: store).preferredColorScheme(.dark))
        NSApp.activate(ignoringOtherApps: true)
        editor.makeKeyAndOrderFront(nil)
        defer { editor.close() }
        try await Task.sleep(nanoseconds: 350_000_000)
        try capture(editor, to: workspace.appendingPathComponent(".work/mac-1.2-editor.png"))
        editor.orderOut(nil)

        let keyEditor = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 560, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
        keyEditor.isReleasedWhenClosed = false
        keyEditor.contentView = NSHostingView(rootView: HostEditor(host: Host(auth: .key), store: store).preferredColorScheme(.dark))
        keyEditor.makeKeyAndOrderFront(nil)
        defer { keyEditor.close() }
        try await Task.sleep(nanoseconds: 250_000_000)
        try capture(keyEditor, to: workspace.appendingPathComponent(".work/mac-1.2-key-form.png"))
        keyEditor.orderOut(nil)

        let paste = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 580, height: 460), styleMask: [.titled], backing: .buffered, defer: false)
        paste.isReleasedWhenClosed = false
        paste.contentView = NSHostingView(rootView: KeyPasteView(save: { _ in }).preferredColorScheme(.dark))
        paste.makeKeyAndOrderFront(nil)
        defer { paste.close() }
        try await Task.sleep(nanoseconds: 250_000_000)
        try capture(paste, to: workspace.appendingPathComponent(".work/mac-1.2-paste-key.png"))
        paste.orderOut(nil)

        let host = Host(name: "Web server", address: "192.168.1.42", username: "deploy", secret: "fixture-password")
        try store.save(host)
        main.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 350_000_000)
        try capture(main, to: workspace.appendingPathComponent(".work/mac-1.2-host.png"))
        try store.save(Host(name: "Build runner", address: "build.internal", username: "ci", group: "Work", auth: .none))
        try store.save(Host(name: "Database", address: "db.internal", username: "admin", group: "Work", auth: .none))
        try store.save(Host(name: "Home gateway", address: "gateway.local", username: "home", group: "Personal", auth: .none))
        try await Task.sleep(nanoseconds: 300_000_000)
        try capture(main, to: workspace.appendingPathComponent(".work/mac-1.2-hosts-grouped.png"))

        let pair = NSWindow(contentRect: NSRect(x: 90, y: 90, width: 720, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        pair.isReleasedWhenClosed = false
        pair.contentView = NSHostingView(rootView: SharingView(store: store, sharing: sharing).preferredColorScheme(.dark))
        pair.makeKeyAndOrderFront(nil)
        defer { pair.close() }
        sharing.port = String(Int.random(in: 30000...60000))
        sharing.inviteAutomatically()
        XCTAssertNotNil(sharing.invitation, sharing.error ?? "No invitation")
        try await Task.sleep(nanoseconds: 350_000_000)
        try capture(pair, to: workspace.appendingPathComponent(".work/mac-1.2-pairing.png"))
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
    private func click(_ window: NSWindow, x: CGFloat, y: CGFloat) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    @MainActor
    private func visibleWords(_ window: NSWindow) throws -> String {
        let view = try XCTUnwrap(window.contentView)
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    @MainActor
    func testEditorAndPairingControlsRespondToClicks() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = workspace.appendingPathComponent(".work/ui-actions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        try vault.save(library)
        let store = LibraryStore(testVault: vault, library: library)
        let sharing = SharingService(store: store)
        store.onLock = { [weak sharing] in sharing?.stop() }
        defer { store.lock() }

        let editor = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 560, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
        editor.isReleasedWhenClosed = false
        editor.contentView = NSHostingView(rootView: HostEditor(host: Host(auth: .none), store: store).preferredColorScheme(.dark))
        editor.makeKeyAndOrderFront(nil)
        defer { editor.close() }
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertFalse(try visibleWords(editor).contains("Display name"))
        try click(editor, x: 90, y: 209)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertTrue(try visibleWords(editor).contains("Display name"))
        try capture(editor, to: workspace.appendingPathComponent(".work/mac-1.2-editor-expanded.png"))
        try click(editor, x: 90, y: 364)
        try await Task.sleep(nanoseconds: 500_000_000)
        try capture(editor, to: workspace.appendingPathComponent(".work/mac-1.2-editor-collapsed.png"))
        XCTAssertFalse(try visibleWords(editor).contains("Display name"))
        editor.orderOut(nil)

        let pair = NSWindow(contentRect: NSRect(x: 90, y: 90, width: 720, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        pair.isReleasedWhenClosed = false
        pair.contentView = NSHostingView(rootView: SharingView(store: store, sharing: sharing).preferredColorScheme(.dark))
        pair.makeKeyAndOrderFront(nil)
        defer { pair.close() }
        sharing.port = String(Int.random(in: 30000...60000))
        sharing.inviteAutomatically()
        let firstInvitation = try XCTUnwrap(sharing.invitation)
        try await Task.sleep(nanoseconds: 350_000_000)
        try click(pair, x: 585, y: 624)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(try visibleWords(pair).contains("Network for pairing"))
        try capture(pair, to: workspace.appendingPathComponent(".work/mac-1.2-network-options.png"))
        try click(pair, x: 50, y: 624)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(try visibleWords(pair).contains("Devices"))
        if let choice = sharing.networks.enumerated().first(where: { $0.element.address != sharing.address }) {
            try click(pair, x: 585, y: 624)
            try await Task.sleep(nanoseconds: 200_000_000)
            try click(pair, x: 150, y: 514 - CGFloat(choice.offset) * 55)
            try await Task.sleep(nanoseconds: 350_000_000)
            XCTAssertEqual(sharing.address, choice.element.address)
            XCTAssertNotEqual(sharing.invitation?.pairId, firstInvitation.pairId)
            XCTAssertTrue(try visibleWords(pair).contains("Devices"))
        }
    }

    @MainActor
    func testHostEditorSaveClickPersistsAndReopens() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = workspace.appendingPathComponent(".work/editor-save-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        try vault.save(library)
        let store = LibraryStore(testVault: vault, library: library)
        defer { store.lock() }
        let draft = Host(address: "qa.internal", username: "tester", group: "Work", auth: .none)
        var savedID: String?
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 560, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HostEditor(host: draft, store: store, onSaved: { savedID = $0.id }).preferredColorScheme(.dark))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(nanoseconds: 250_000_000)
        try click(window, x: 490, y: 27)
        try await Task.sleep(nanoseconds: 250_000_000)
        let saved = try XCTUnwrap(store.library.hosts.first)
        XCTAssertEqual(saved.id, savedID)
        XCTAssertEqual(saved.name, "qa.internal")
        XCTAssertEqual(saved.group, "Work")
        XCTAssertEqual(try vault.load().hosts, [saved])
        window.contentView = NSHostingView(rootView: HostEditor(host: saved, store: store).preferredColorScheme(.dark))
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(try visibleWords(window).contains("Edit host"))
        XCTAssertTrue(try visibleWords(window).contains("Work"))
    }

    @MainActor
    func testHostEditorShowsValidationProgressAndCancelDiscardsSave() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = workspace.appendingPathComponent(".work/editor-cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        try vault.save(library)
        let store = LibraryStore(testVault: vault, library: library)
        defer { store.lock() }
        let draft = Host(address: "cancel.internal", username: "tester", auth: .none)
        var saveCount = 0
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 560, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HostEditor(host: draft, store: store, prepare: { host, port, password, passphrase in
            usleep(1_500_000)
            return try HostEditor.preparedHost(host, portText: port, password: password, passphrase: passphrase)
        }, onSaved: { _ in saveCount += 1 }).preferredColorScheme(.dark))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(nanoseconds: 250_000_000)
        try click(window, x: 490, y: 27)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(try visibleWords(window).contains("Validating"))
        try click(window, x: 390, y: 27)
        try await Task.sleep(nanoseconds: 1_700_000_000)
        XCTAssertEqual(saveCount, 0)
        XCTAssertTrue(store.library.hosts.isEmpty)
        XCTAssertTrue(try vault.load().hosts.isEmpty)
    }

    @MainActor
    func testPrivateKeyPasteButtonOpensAndCancelsEditor() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = workspace.appendingPathComponent(".work/paste-button-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        try vault.save(library)
        let store = LibraryStore(testVault: vault, library: library)
        defer { store.lock() }
        var draft = Host(auth: .key)
        draft.privateKey = try encryptedPEMFixtures().pkcs8
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 560, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HostEditor(host: draft, store: store).preferredColorScheme(.dark))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(nanoseconds: 250_000_000)
        try click(window, x: 465, y: 227)
        try await Task.sleep(nanoseconds: 300_000_000)
        let sheet = try XCTUnwrap(window.attachedSheet)
        XCTAssertTrue(try visibleWords(sheet).contains("Paste private key"))
        try click(sheet, x: 435, y: 27)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(window.attachedSheet)
        XCTAssertTrue(try visibleWords(window).contains("Private key added"))
        XCTAssertTrue(store.library.hosts.isEmpty)
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
        let refused = await waitForPhase(rejected, .failed, seconds: 8)
        XCTAssertTrue(refused, "OpenSSH did not reject the changed server key.")
        XCTAssertTrue(rejected.failure?.contains("server key") == true)
        XCTAssertFalse(String(data: rejected.terminal.getTerminal().getBufferAsData(kind: .normal), encoding: .utf8)?.contains("harbor-fixture $") ?? false)
    }

    @MainActor
    func testNoPasswordThroughNativeTerminal() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = workspace.appendingPathComponent(".work/ssh-fixture-hosts-none.json")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else { throw XCTSkip("Disposable no-password SSH fixture is unavailable.") }
        let fixtures = try JSONDecoder().decode([WireHost].self, from: Data(contentsOf: fixtureURL))
        let fixture = try XCTUnwrap(fixtures.first { $0.authType == "none" })
        XCTAssertTrue(fixture.password.isEmpty)
        XCTAssertTrue(fixture.privateKey.isEmpty)
        XCTAssertTrue(fixture.passphrase.isEmpty)
        let port = 48607
        var host = Host(name: fixture.name, address: "127.0.0.1", port: port, username: fixture.username, auth: .none)
        host.knownHosts = "[127.0.0.1]:\(port) \(fixture.hostKey)\n"
        let scan = try await SSH.inspect(host)
        XCTAssertTrue(scan.records.contains(fixture.hostKey))
        let root = workspace.appendingPathComponent(".work/no-password-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try TerminalSession(host: host, root: root)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = session.terminal
        window.makeKeyAndOrderFront(nil)
        defer { session.close(); window.close() }
        let ready = await waitForTerminal(session, text: "harbor-fixture $", seconds: 15)
        XCTAssertTrue(ready, "No-password SSH did not reach the shell prompt; status \(session.status).")
        guard ready else { return }
        let command = Array("printf 'HARBOR_NONE_%s_DONE\\n' 'EXECUTED'\r".utf8)
        session.terminal.send(data: command[...])
        let executed = await waitForTerminal(session, text: "HARBOR_NONE_EXECUTED_DONE", seconds: 8)
        XCTAssertTrue(executed, "No-password SSH did not execute a command.")
        let sessions = root.appendingPathComponent("Sessions")
        let entries = try FileManager.default.contentsOfDirectory(atPath: sessions.path)
        let files = try FileManager.default.contentsOfDirectory(atPath: sessions.appendingPathComponent(try XCTUnwrap(entries.first)).path)
        XCTAssertEqual(Set(files), ["known_hosts", "ssh-diagnostics"])
    }

    @MainActor
    func testRemoteShellExitClosesTabAfterNestedShell() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = workspace.appendingPathComponent(".work/ssh-1.2-hosts.json")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else { throw XCTSkip("Disposable SSH fixture is unavailable.") }
        let fixtures = try JSONDecoder().decode([WireHost].self, from: Data(contentsOf: fixtureURL))
        let fixture = try XCTUnwrap(fixtures.first { $0.authType == "none" })
        let directory = workspace.appendingPathComponent(".work/exit-vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        var host = Host(name: "Shell exit", address: "127.0.0.1", port: 48610, username: fixture.username, auth: .none)
        host.knownHosts = "[127.0.0.1]:48610 \(fixture.hostKey)\n"
        library.hosts = [host]
        try vault.save(library)
        let store = LibraryStore(testVault: vault, library: library)
        let sharing = SharingService(store: store)
        store.onLock = { [weak sharing] in sharing?.stop() }
        defer { store.lock() }
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 900, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(store: store, sharing: sharing).preferredColorScheme(.dark))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        store.connect(host)
        let session = try XCTUnwrap(store.sessions.first)
        XCTAssertNil(session.terminal.superview)
        let ready = await waitForPhase(session, .ready, seconds: 12)
        XCTAssertTrue(ready, session.failure ?? session.status)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNotNil(session.terminal.superview)
        session.terminal.send(data: Array("sh\r".utf8)[...])
        try await Task.sleep(nanoseconds: 250_000_000)
        let marker = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        session.terminal.send(data: Array("printf 'HARBOR_SUB_%s_DONE\\n' '\(marker)'\r".utf8)[...])
        let executed = await waitForTerminal(session, text: "HARBOR_SUB_\(marker)_DONE", seconds: 6)
        XCTAssertTrue(executed)
        session.terminal.send(data: Array("exit\r".utf8)[...])
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(session.phase, .ready)
        session.terminal.send(data: Array("exit\r".utf8)[...])
        for _ in 0..<60 {
            if store.sessions.isEmpty { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(store.sessions.isEmpty, "The completed shell left its terminal tab open.")
        XCTAssertNil(store.activeSession)
    }

    @MainActor
    func testAbruptSSHTransportFailureKeepsRecoveryTab() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = workspace.appendingPathComponent(".work/ssh-1.2-disconnect.json")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else { throw XCTSkip("Abrupt SSH fixture is unavailable.") }
        let fixture = try JSONDecoder().decode(WireHost.self, from: Data(contentsOf: fixtureURL))
        let directory = workspace.appendingPathComponent(".work/disconnect-vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        var host = Host(name: "Disconnect fixture", address: "127.0.0.1", port: 48611, username: fixture.username, auth: .none)
        host.knownHosts = "[127.0.0.1]:48611 \(fixture.hostKey)\n"
        library.hosts = [host]
        try vault.save(library)
        let store = LibraryStore(testVault: vault, library: library)
        defer { store.lock() }
        let sharing = SharingService(store: store)
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(store: store, sharing: sharing).preferredColorScheme(.dark))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        store.connect(host)
        let session = try XCTUnwrap(store.sessions.first)
        let ready = await waitForPhase(session, .ready, seconds: 5)
        XCTAssertTrue(ready, session.failure ?? session.status)
        guard ready else { return }
        let failed = await waitForPhase(session, .failed, seconds: 8)
        XCTAssertTrue(failed, session.failure ?? session.status)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.activeSession, session.id)
        XCTAssertNil(session.terminal.superview)
        XCTAssertTrue(session.failure?.contains("unexpectedly") == true)
        try capture(window, to: workspace.appendingPathComponent(".work/mac-1.2-disconnected.png"))
    }

    @MainActor
    func testPrivateKeyImportAndPasteValidationWithVaultReload() throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = workspace.appendingPathComponent(".work/ssh-1.2-hosts.json")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else { throw XCTSkip("Disposable key fixture is unavailable.") }
        let fixtures = try JSONDecoder().decode([WireHost].self, from: Data(contentsOf: fixtureURL))
        let plain = try XCTUnwrap(fixtures.first { $0.authType == "key" && $0.passphrase.isEmpty })
        let encrypted = try XCTUnwrap(fixtures.first { $0.authType == "key" && !$0.passphrase.isEmpty })
        let imported = try PrivateKeyValidator.validate(plain.privateKey)
        XCTAssertEqual(try PrivateKeyValidator.validate(plain.privateKey.replacingOccurrences(of: "\n", with: "\r\n")), imported)
        XCTAssertNotNil(try PrivateKeyValidator.validate(encrypted.privateKey).range(of: "OPENSSH PRIVATE KEY"))
        XCTAssertThrowsError(try PrivateKeyValidator.validate("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA"))
        XCTAssertThrowsError(try PrivateKeyValidator.validate(String(plain.privateKey.dropLast(40))))
        XCTAssertThrowsError(try PrivateKeyValidator.validate(String(repeating: "a", count: 256 * 1024 + 1)))
        let directory = workspace.appendingPathComponent(".work/key-vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var host = Host(name: "Imported key", address: "127.0.0.1", username: "harbor", auth: .key)
        host.privateKey = imported
        host.secret = encrypted.passphrase
        let saved = try HostEditor.preparedHost(host, portText: "22", password: "", passphrase: encrypted.passphrase)
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        library.hosts = [saved]
        try vault.save(library)
        XCTAssertNil(try Data(contentsOf: vault.archive).range(of: Data(imported.utf8)))
        XCTAssertEqual(try vault.load().hosts.first?.privateKey, imported)
        XCTAssertEqual(try vault.load().hosts.first?.secret, encrypted.passphrase)
    }

    @MainActor
    func testEncryptedPEMPassphraseValidationAndVaultReload() throws {
        let fixtures = try encryptedPEMFixtures()
        let imported = try PrivateKeyValidator.validate(fixtures.pkcs8)
        XCTAssertEqual(imported, fixtures.pkcs8)
        XCTAssertEqual(try PrivateKeyValidator.validate(fixtures.traditionalEC), fixtures.traditionalEC)
        var host = Host(name: "Encrypted PEM", address: "127.0.0.1", username: "harbor", auth: .key)
        host.privateKey = imported
        let original = host
        XCTAssertThrowsError(try HostEditor.preparedHost(host, portText: "22", password: "", passphrase: "")) {
            XCTAssertEqual($0.localizedDescription, "This private key is encrypted. Enter its passphrase.")
        }
        XCTAssertEqual(host, original)
        XCTAssertThrowsError(try HostEditor.preparedHost(host, portText: "22", password: "", passphrase: "wrong-passphrase")) {
            XCTAssertEqual($0.localizedDescription, "The private key passphrase is incorrect, or the encrypted key is damaged.")
        }
        let invalidPassphrase = "The private key passphrase must be at most 4096 UTF-8 bytes and cannot contain NUL or line break characters."
        for passphrase in ["nul\0byte", "line\nfeed", "carriage\rreturn", String(repeating: "x", count: 4097)] {
            XCTAssertThrowsError(try HostEditor.preparedHost(host, portText: "22", password: "", passphrase: passphrase)) {
                XCTAssertEqual($0.localizedDescription, invalidPassphrase)
            }
        }
        XCTAssertThrowsError(try HostEditor.preparedHost(host, portText: "22", password: "", passphrase: String(repeating: "x", count: 4096))) {
            XCTAssertEqual($0.localizedDescription, "The private key passphrase is incorrect, or the encrypted key is damaged.")
        }
        XCTAssertEqual(host, original)
        let saved = try HostEditor.preparedHost(host, portText: "22", password: "", passphrase: fixtures.passphrase)
        XCTAssertEqual(saved.privateKey, fixtures.pkcs8)
        XCTAssertEqual(saved.secret, fixtures.passphrase)
        XCTAssertEqual(WireHost(saved).privateKey, fixtures.pkcs8)
        XCTAssertEqual(WireHost(saved).passphrase, fixtures.passphrase)
        XCTAssertNoThrow(try PrivateKeyValidator.validate(fixtures.traditionalEC, passphrase: fixtures.passphrase))
        XCTAssertThrowsError(try PrivateKeyValidator.validate(fixtures.traditionalEC, passphrase: "wrong-passphrase"))
        var lines = fixtures.pkcs8.split(whereSeparator: \.isNewline).map(String.init)
        var encrypted = try XCTUnwrap(Data(base64Encoded: lines.dropFirst().dropLast().joined()))
        encrypted[encrypted.count - 1] ^= 1
        let encoded = encrypted.base64EncodedString(options: .lineLength64Characters).replacingOccurrences(of: "\r\n", with: "\n")
        let corrupted = "-----BEGIN ENCRYPTED PRIVATE KEY-----\n\(encoded)\n-----END ENCRYPTED PRIVATE KEY-----\n"
        XCTAssertNoThrow(try PrivateKeyValidator.validate(corrupted))
        XCTAssertThrowsError(try PrivateKeyValidator.validate(corrupted, passphrase: fixtures.passphrase)) {
            XCTAssertEqual($0.localizedDescription, "The private key passphrase is incorrect, or the encrypted key is damaged.")
        }
        lines.remove(at: lines.count / 2)
        XCTAssertThrowsError(try PrivateKeyValidator.validate(lines.joined(separator: "\n")))
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = workspace.appendingPathComponent(".work/encrypted-pem-vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = try Vault(directory: directory, key: SymmetricKey(size: .bits256))
        var library = Library()
        library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        library.hosts = [saved]
        try vault.save(library)
        let archive = try Data(contentsOf: vault.archive)
        XCTAssertNil(archive.range(of: Data(fixtures.pkcs8.utf8)))
        XCTAssertNil(archive.range(of: Data(fixtures.passphrase.utf8)))
        let reloaded = try XCTUnwrap(try vault.load().hosts.first)
        XCTAssertEqual(reloaded.privateKey, fixtures.pkcs8)
        XCTAssertEqual(reloaded.secret, fixtures.passphrase)
    }

    @MainActor
    func testEncryptedPEMThroughNativeTerminal() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = workspace.appendingPathComponent(".work/ssh-encrypted-pem-host.json")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else { throw XCTSkip("Disposable encrypted PEM SSH fixture is unavailable.") }
        let fixture = try JSONDecoder().decode(WireHost.self, from: Data(contentsOf: fixtureURL))
        var host = Host(name: fixture.name, address: fixture.hostname, port: fixture.port, username: fixture.username, auth: .key)
        host.privateKey = fixture.privateKey
        host.secret = fixture.passphrase
        host.knownHosts = "[\(fixture.hostname)]:\(fixture.port) \(fixture.hostKey)\n"
        host = try HostEditor.preparedHost(host, portText: String(fixture.port), password: "", passphrase: fixture.passphrase)
        let root = workspace.appendingPathComponent(".work/encrypted-pem-ssh-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try TerminalSession(host: host, root: root)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 800, height: 500), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = session.terminal
        window.makeKeyAndOrderFront(nil)
        defer { session.close(); window.close() }
        let ready = await waitForPhase(session, .ready, seconds: 20)
        XCTAssertTrue(ready, session.failure ?? session.status)
        guard ready else { return }
        let marker = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        session.terminal.send(data: Array("printf 'HARBOR_ENCRYPTED_PEM_%s_DONE\\n' '\(marker)'\r".utf8)[...])
        let executed = await waitForTerminal(session, text: "HARBOR_ENCRYPTED_PEM_\(marker)_DONE", seconds: 8)
        XCTAssertTrue(executed)
        XCTAssertEqual(session.host.privateKey, fixture.privateKey)
        XCTAssertEqual(session.host.secret, fixture.passphrase)
    }

    @MainActor
    func testConnectionProgressAndSpacedKnownHostsPathAgainstDisposableServer() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = workspace.appendingPathComponent(".work/ssh-1.2-hosts.json")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else { throw XCTSkip("Disposable progress SSH fixture is unavailable.") }
        let fixtures = try JSONDecoder().decode([WireHost].self, from: Data(contentsOf: fixtureURL))
        XCTAssertEqual(fixtures.count, 4)
        let root = workspace.appendingPathComponent(".work/Harbor QA Application Support \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let port = 48610
        for fixture in fixtures.filter({ $0.authType == "none" || ($0.authType == "key" && $0.passphrase.isEmpty) }) {
            let auth = try XCTUnwrap(Host.Authentication(rawValue: fixture.authType))
            var host = Host(name: fixture.name, address: "127.0.0.1", port: port, username: fixture.username, auth: auth)
            host.secret = auth == .password ? fixture.password : fixture.passphrase
            host.privateKey = fixture.privateKey
            host.knownHosts = "[127.0.0.1]:\(port) \(fixture.hostKey)\n"
            let session = try TerminalSession(host: host, root: root)
            let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 850, height: 560), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SessionWorkspace(session: session, active: true, retry: {}, edit: {}, cancel: {}).background(Palette.canvas).preferredColorScheme(.dark))
            window.makeKeyAndOrderFront(nil)
            var closed = false
            defer { if !closed { session.close(); window.close() } }
            if auth == .none { try capture(window, to: workspace.appendingPathComponent(".work/mac-1.2-connecting.png")) }
            try await Task.sleep(nanoseconds: 150_000_000)
            if session.phase != .ready { XCTAssertNil(session.terminal.superview, "The terminal mounted before the shell was accepted.") }
            let opened = await waitForPhase(session, .ready, seconds: 20)
            let pendingOutput = String(data: session.terminal.getTerminal().getBufferAsData(kind: .normal), encoding: .utf8) ?? ""
            XCTAssertTrue(opened, "Shell was not accepted for \(fixture.name): \(session.failure ?? session.status), latest milestone \(session.lastMilestone.title), password prompt \(pendingOutput.localizedCaseInsensitiveContains("password:")), permission denied \(pendingOutput.contains("Permission denied"))")
            guard opened else { return }
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertNotNil(session.terminal.superview, "The terminal did not mount after shell acceptance.")
            let prompt = await waitForTerminal(session, text: "harbor-fixture $", seconds: 8)
            XCTAssertTrue(prompt, "The real terminal did not appear after shell acceptance for \(fixture.name).")
            let marker = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let command = Array("printf 'HARBOR_EXEC_%s_DONE\\n' '\(marker)'\r".utf8)
            session.terminal.send(data: command[...])
            let executed = await waitForTerminal(session, text: "HARBOR_EXEC_\(marker)_DONE", seconds: 8)
            XCTAssertTrue(executed)
            session.close()
            window.close()
            closed = true
            let entries = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Sessions").path)
            XCTAssertTrue(entries.isEmpty)
        }
        let fixture = try XCTUnwrap(fixtures.first { $0.authType == "none" })
        var wrong = Host(name: "Changed server key", address: "127.0.0.1", port: port, username: fixture.username, auth: .none)
        let parts = fixture.hostKey.split(separator: " ")
        var bytes = try XCTUnwrap(Data(base64Encoded: String(try XCTUnwrap(parts.last))))
        bytes[bytes.count - 1] ^= 1
        wrong.knownHosts = "[127.0.0.1]:\(port) \(parts[0]) \(bytes.base64EncodedString())\n"
        let rejected = try TerminalSession(host: wrong, root: root)
        let failureWindow = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 850, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        failureWindow.isReleasedWhenClosed = false
        failureWindow.contentView = NSHostingView(rootView: SessionWorkspace(session: rejected, active: true, retry: {}, edit: {}, cancel: {}).background(Palette.canvas).preferredColorScheme(.dark))
        failureWindow.makeKeyAndOrderFront(nil)
        defer { rejected.close(); failureWindow.close() }
        let failed = await waitForPhase(rejected, .failed, seconds: 12)
        XCTAssertTrue(failed)
        XCTAssertEqual(rejected.lastMilestone, .verifying)
        XCTAssertTrue(rejected.failure?.contains("server key") == true)
        try capture(failureWindow, to: workspace.appendingPathComponent(".work/mac-1.2-key-rejected.png"))
        rejected.close()
        let cancelled = try TerminalSession(host: Host(name: fixture.name, address: "127.0.0.1", port: port, username: fixture.username, auth: .none, knownHosts: "[127.0.0.1]:\(port) \(fixture.hostKey)\n"), root: root)
        cancelled.close()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(cancelled.phase, .ended)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Sessions").path)
        XCTAssertTrue(remaining.isEmpty)
    }

    @MainActor
    private func waitForPhase(_ session: TerminalSession, _ phase: ConnectionPhase, seconds: Int) async -> Bool {
        for _ in 0..<(seconds * 10) {
            if session.phase == phase { return true }
            if session.phase == .failed && phase != .failed { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    @MainActor
    func testPreauthenticationBannerCannotAdvanceConnectionProgress() async throws {
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = workspace.appendingPathComponent(".work/ssh-progress-banner.json")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else { throw XCTSkip("Disposable delayed banner fixture is unavailable.") }
        let fixture = try JSONDecoder().decode(WireHost.self, from: Data(contentsOf: fixtureURL))
        let root = workspace.appendingPathComponent(".work/banner-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        var host = Host(name: fixture.name, address: "127.0.0.1", port: 48609, username: fixture.username, auth: .none)
        host.knownHosts = "[127.0.0.1]:48609 \(fixture.hostKey)\n"
        let session = try TerminalSession(host: host, root: root)
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 850, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SessionWorkspace(session: session, active: true, retry: {}, edit: {}, cancel: {}).background(Palette.canvas).preferredColorScheme(.dark))
        window.makeKeyAndOrderFront(nil)
        defer { session.close(); window.close() }
        let verifying = await waitForPhase(session, .authenticating, seconds: 5)
        XCTAssertTrue(verifying)
        try await Task.sleep(nanoseconds: 800_000_000)
        let output = String(data: session.terminal.getTerminal().getBufferAsData(kind: .normal), encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("https://login.tailscale.com/a/harbor-fixture"))
        XCTAssertTrue(output.contains("Authenticated to 127.0.0.1"))
        XCTAssertEqual(session.phase, .authenticating)
        XCTAssertEqual(session.lastMilestone, .authenticating)
        try capture(window, to: workspace.appendingPathComponent(".work/mac-1.1.2-banner.png"))
        let opened = await waitForPhase(session, .ready, seconds: 12)
        XCTAssertTrue(opened, session.failure ?? session.status)
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
    func testHostEditorDefaultsNameOnlyAtSaveAndRejectsInvalidKeyDraft() throws {
        var host = Host(address: "example.com", username: "deploy")
        XCTAssertEqual(host.name, "")
        let saved = try HostEditor.preparedHost(host, portText: "22", password: "fixture-secret", passphrase: "")
        XCTAssertEqual(saved.name, "example.com")
        XCTAssertEqual(saved.secret, "fixture-secret")
        host.auth = .key
        host.privateKey = "-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----"
        XCTAssertThrowsError(try HostEditor.preparedHost(host, portText: "2222", password: "unused", passphrase: "fixture-passphrase"))
        XCTAssertThrowsError(try HostEditor.preparedHost(host, portText: "0", password: "", passphrase: ""))
    }

    @MainActor
    func testNoPasswordHostClearsInactiveCredentialsAndExportsNone() throws {
        var host = Host(name: "Tailnet", address: "server.tailnet.ts.net", username: "deploy", auth: .none)
        try host.validate()
        host.secret = "old-password"
        host.privateKey = "-----BEGIN PRIVATE KEY-----\nold\n-----END PRIVATE KEY-----"
        XCTAssertThrowsError(try host.validate())
        let saved = try HostEditor.preparedHost(host, portText: "22", password: "draft-password", passphrase: "draft-passphrase")
        try saved.validate()
        XCTAssertEqual(saved.auth.rawValue, "none")
        XCTAssertTrue(saved.secret.isEmpty)
        XCTAssertTrue(saved.privateKey.isEmpty)
        let wire = WireHost(saved)
        XCTAssertEqual(wire.authType, "none")
        XCTAssertTrue(wire.password.isEmpty)
        XCTAssertTrue(wire.privateKey.isEmpty)
        XCTAssertTrue(wire.passphrase.isEmpty)
        host.auth = .password
        XCTAssertNoThrow(try host.validate())
        host.secret = ""
        XCTAssertThrowsError(try host.validate())
        host.auth = .key
        XCTAssertNoThrow(try host.validate())
        host.privateKey = ""
        XCTAssertThrowsError(try host.validate())
    }

    private func encryptedPEMFixtures() throws -> (pkcs8: String, traditionalEC: String, passphrase: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Harbor-Encrypted-PEM-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let rsa = root.appendingPathComponent("rsa.pem")
        let pkcs8 = root.appendingPathComponent("rsa-encrypted.pem")
        let ec = root.appendingPathComponent("ec.pem")
        let encryptedEC = root.appendingPathComponent("ec-encrypted.pem")
        let passphrase = "fixture encrypted PEM passphrase"
        try runOpenSSL(["genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:1024", "-out", rsa.path])
        try runOpenSSL(["pkcs8", "-topk8", "-in", rsa.path, "-out", pkcs8.path, "-v2", "aes-256-cbc", "-passout", "stdin"], input: passphrase)
        try runOpenSSL(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", ec.path])
        try runOpenSSL(["ec", "-in", ec.path, "-out", encryptedEC.path, "-aes256", "-passout", "stdin"], input: passphrase)
        return (try String(contentsOf: pkcs8, encoding: .utf8), try String(contentsOf: encryptedEC, encoding: .utf8), passphrase)
    }

    private func runOpenSSL(_ arguments: [String], input: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        let pipe = input == nil ? nil : Pipe()
        if let pipe { process.standardInput = pipe }
        else { process.standardInput = FileHandle.nullDevice }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if let input, let pipe {
            try pipe.fileHandleForWriting.write(contentsOf: Data((input + "\n").utf8))
            try pipe.fileHandleForWriting.close()
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw HarborError.message("Could not create the encrypted PEM test fixture.") }
    }

}
