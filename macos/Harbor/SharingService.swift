import AppKit
import CryptoKit
import Darwin
import Foundation

struct Invitation: Codable {
    var version = 1
    let url: String
    let vaultId: String
    let pairId: String
    let secret: String
    let publicKey: String
    let expiresAt: Int64
    let desktopName: String
}

struct PairRequest: Codable {
    let deviceId: String
    let deviceName: String
    let clientNonce: String
}

struct PairResponse: Codable {
    var version = 1
    let deviceId: String
    let vaultId: String
    let syncKey: String
    let desktopName: String
}

struct SyncRequest: Codable {
    let version: Int
    let vaultId: String
    let requestId: String
}

struct PendingPair: Identifiable {
    let id: String
    let name: String
    let nonce: String
    let code: String
}

struct ApprovedPairReply {
    let secret: Data
    let deviceID: String
    let nonce: String
    let response: Envelope
    let expiresAt: Int64

    func accepts(_ request: PairRequest) -> Bool { request.deviceId == deviceID && request.clientNonce == nonce }
}

struct ApprovedReplyCache {
    private var replies: [String: ApprovedPairReply] = [:]
    var count: Int { replies.count }
    var nextExpiry: Int64? { replies.values.map(\.expiresAt).min() }

    mutating func purge(at now: Int64) { replies = replies.filter { $0.value.expiresAt > now } }
    mutating func insert(_ reply: ApprovedPairReply, pairID: String, now: Int64) throws {
        purge(at: now)
        guard reply.expiresAt > now, replies.count < 32 || replies[pairID] != nil else { throw HarborError.message("Pairing limit reached. Wait for an older invitation to expire.") }
        replies[pairID] = reply
    }
    func reply(for pairID: String, now: Int64) -> ApprovedPairReply? {
        guard let reply = replies[pairID], reply.expiresAt > now else { return nil }
        return reply
    }
    mutating func revoke(_ deviceID: String) { replies = replies.filter { $0.value.deviceID != deviceID } }
    mutating func removeAll() { replies.removeAll() }
}

@MainActor
final class SharingService: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var invitation: Invitation?
    @Published private(set) var pending: PendingPair?
    @Published var address = SharingService.localAddress()
    @Published var port = "45873"
    @Published var error: String?
    @Published private(set) var pairingResult: String?
    private let store: LibraryStore
    private var server: HTTPServer?
    private var approved: Envelope?
    private var approvedReplies = ApprovedReplyCache()
    private var approvedExpiry: DispatchWorkItem?
    private var denied = false
    private var attempts: [Date] = []
    private var expiry: DispatchWorkItem?

    init(store: LibraryStore) { self.store = store }
    var approvedPairing: Bool { approved != nil }

    func dismissInvitation() { if approved == nil { cancelInvitation() } }

    var invitationText: String {
        guard let invitation, let data = try? JSONEncoder().encode(invitation) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func start() {
        do {
            guard store.loaded, let port = UInt16(port), port > 0, Self.isPrivateAddress(address) else { throw HarborError.message("Enter a local IP address and a port from 1 to 65535.") }
            let server = HTTPServer { [weak self] request in self?.handle(request) ?? HTTPResponse(503) }
            server.failed = { [weak self] error in self?.stop(); self?.error = "Sharing could not start: \(error)" }
            try server.start(port: port)
            self.server = server
            enabled = true
        } catch { self.error = error.localizedDescription }
    }

    func stop() {
        server?.stop()
        server = nil
        enabled = false
        cancelInvitation()
        approvedExpiry?.cancel()
        approvedExpiry = nil
        approvedReplies.removeAll()
        attempts.removeAll()
    }

    func invite() {
        do {
            if !enabled { start() }
            guard enabled else { return }
            purgeApprovedReplies()
            guard approvedReplies.count < 32 else { throw HarborError.message("Pairing limit reached. Wait for an older invitation to expire.") }
            cancelInvitation()
            let signing = try signingKey()
            let ip = address.contains(":") ? "[\(address)]" : address
            let invitation = Invitation(url: "http://\(ip):\(port)", vaultId: store.library.desktopID,
                                        pairId: UUID().uuidString.lowercased(), secret: SyncCrypto.random(32).base64EncodedString(),
                                        publicKey: signing.publicKey.rawRepresentation.base64EncodedString(),
                                        expiresAt: Int64(Date().timeIntervalSince1970) + 300,
                                        desktopName: Foundation.Host.current().localizedName ?? "Harbor on Mac")
            self.invitation = invitation
            let expiry = DispatchWorkItem { [weak self] in self?.cancelInvitation() }
            self.expiry = expiry
            DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: expiry)
        } catch { self.error = error.localizedDescription }
    }

    func cancelInvitation() {
        expiry?.cancel()
        expiry = nil
        invitation = nil
        pending = nil
        approved = nil
        denied = false
        pairingResult = nil
    }

    func approve() {
        do {
            guard !denied, approved == nil, let invitation, let pending, invitation.expiresAt > Int64(Date().timeIntervalSince1970),
                  let secret = Data(base64Encoded: invitation.secret) else { throw HarborError.message("The invitation has expired.") }
            var next = store.library
            guard next.devices.count < 100 else { throw HarborError.message("Revoke an old device before pairing more than 100 devices.") }
            guard !next.devices.contains(where: { $0.id == pending.id }) else { throw HarborError.message("This device is already paired. Forget this desktop on the phone before pairing again.") }
            let syncKey = SyncCrypto.random(32).base64EncodedString()
            let device = PairedDevice(id: pending.id, name: pending.name, secret: syncKey, pairedAt: Int64(Date().timeIntervalSince1970))
            next.devices.append(device)
            let response = PairResponse(deviceId: pending.id, vaultId: next.desktopID, syncKey: syncKey, desktopName: invitation.desktopName)
            let envelope = try SyncCrypto.seal(response, key: secret, aad: "harbor/pair-response/v1/\(invitation.pairId)")
            var replies = approvedReplies
            try replies.insert(ApprovedPairReply(secret: secret, deviceID: pending.id, nonce: pending.nonce, response: envelope, expiresAt: invitation.expiresAt), pairID: invitation.pairId, now: Int64(Date().timeIntervalSince1970))
            try store.commit(next)
            approvedReplies = replies
            purgeApprovedReplies()
            approved = envelope
            pairingResult = "Paired with \(pending.name). Press Sync now on Android to receive your library."
        } catch { self.error = error.localizedDescription }
    }

    func deny() { denied = true; pairingResult = "Pairing request denied." }

    func revoke(_ device: PairedDevice) {
        do {
            var next = store.library
            next.devices.removeAll { $0.id == device.id }
            try store.commit(next)
            approvedReplies.revoke(device.id)
            purgeApprovedReplies()
            if pending?.id == device.id { cancelInvitation() }
        } catch { self.error = error.localizedDescription }
    }

    private func purgeApprovedReplies() {
        approvedExpiry?.cancel()
        approvedExpiry = nil
        let now = Int64(Date().timeIntervalSince1970)
        approvedReplies.purge(at: now)
        guard let next = approvedReplies.nextExpiry else { return }
        let work = DispatchWorkItem { [weak self] in self?.purgeApprovedReplies() }
        approvedExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(max(1, next - now)), execute: work)
    }

    private func signingKey() throws -> Curve25519.Signing.PrivateKey {
        guard let bytes = Data(base64Encoded: store.library.signingKey) else { throw HarborError.message("Desktop signing identity is unavailable.") }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
    }

    private func handle(_ request: HTTPRequest) -> HTTPResponse {
        guard enabled, store.loaded else { return HTTPResponse(503) }
        do {
            if request.path.hasPrefix("/v1/pair/") { return try pair(request) }
            if request.path == "/v1/sync" { return try sync(request) }
            return HTTPResponse(404)
        } catch { return HTTPResponse(400) }
    }

    private func pair(_ request: HTTPRequest) throws -> HTTPResponse {
        let now = Date()
        attempts.removeAll { now.timeIntervalSince($0) > 60 }
        guard attempts.count < 90 else { return HTTPResponse(429) }
        attempts.append(now)
        purgeApprovedReplies()
        let pairID = String(request.path.dropFirst("/v1/pair/".count))
        if let saved = approvedReplies.reply(for: pairID, now: Int64(now.timeIntervalSince1970)) {
            let envelope = try JSONDecoder().decode(Envelope.self, from: request.body)
            let client = try SyncCrypto.open(PairRequest.self, envelope: envelope, key: saved.secret, aad: "harbor/pair-request/v1/\(pairID)")
            guard saved.accepts(client) else { return HTTPResponse(403) }
            return try .json(200, saved.response)
        }
        guard let invitation, request.path == "/v1/pair/\(invitation.pairId)", invitation.expiresAt > Int64(now.timeIntervalSince1970) else { return HTTPResponse(410) }
        guard !denied else { return HTTPResponse(403) }
        guard let key = Data(base64Encoded: invitation.secret) else { return HTTPResponse(410) }
        let envelope = try JSONDecoder().decode(Envelope.self, from: request.body)
        let client = try SyncCrypto.open(PairRequest.self, envelope: envelope, key: key, aad: "harbor/pair-request/v1/\(invitation.pairId)")
        guard Self.validID(client.deviceId), !client.deviceName.isEmpty, client.deviceName.count <= 80,
              client.deviceName.rangeOfCharacter(from: .controlCharacters) == nil,
              let nonce = Data(base64Encoded: client.clientNonce), nonce.count == 32 else { return HTTPResponse(400) }
        if let pending {
            guard pending.id == client.deviceId, pending.nonce == client.clientNonce else { return HTTPResponse(403) }
        } else {
            pending = PendingPair(id: client.deviceId, name: client.deviceName, nonce: client.clientNonce, code: SyncCrypto.comparison(secret: key, nonce: nonce))
        }
        if let approved { return try .json(200, approved) }
        return HTTPResponse(202, Data("{\"status\":\"pending\"}".utf8))
    }

    private func sync(_ request: HTTPRequest) throws -> HTTPResponse {
        let envelope = try JSONDecoder().decode(Envelope.self, from: request.body)
        guard let deviceID = envelope.deviceId, Self.validID(deviceID),
              let device = store.library.devices.first(where: { $0.id == deviceID }),
              let key = Data(base64Encoded: device.secret), key.count == 32 else { return HTTPResponse(403) }
        let client = try SyncCrypto.open(SyncRequest.self, envelope: envelope, key: key, aad: "harbor/sync-request/v1/\(deviceID)")
        guard client.version == 1, client.vaultId == store.library.desktopID,
              let nonce = Data(base64Encoded: client.requestId), nonce.count == 32 else { return HTTPResponse(400) }
        let snapshot = Snapshot(vaultId: store.library.desktopID, revision: store.library.revision,
                                generatedAt: Int64(Date().timeIntervalSince1970), requestId: client.requestId,
                                hosts: store.library.hosts.map(WireHost.init))
        let bytes = try JSONEncoder().encode(snapshot)
        guard bytes.count <= 8 * 1024 * 1024 else { return HTTPResponse(500) }
        let payload = bytes.base64EncodedString()
        let signature = try signingKey().signature(for: Data("harbor.snapshot.v1\n\(payload)".utf8)).base64EncodedString()
        let response = try SyncCrypto.seal(SignedSnapshot(payload: payload, signature: signature), key: key, aad: "harbor/sync-response/v1/\(deviceID)")
        return try .json(200, response)
    }

    static func validID(_ value: String) -> Bool { value == value.lowercased() && UUID(uuidString: value) != nil }

    static func isPrivateAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 {
            let octets = value.split(separator: ".").compactMap { Int($0) }
            guard octets.count == 4 else { return false }
            return octets[0] == 10 || octets[0] == 127 || (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 169 && octets[1] == 254)
        }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, value, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: ipv6) { Array($0) }
            return value == "::1" || bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80)
        }
        return false
    }

    static func localAddress() -> String {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return "127.0.0.1" }
        defer { freeifaddrs(interfaces) }
        var current = interfaces
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), interface.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: host)
                if value != "127.0.0.1", isPrivateAddress(value) { return value }
            }
        }
        return "127.0.0.1"
    }
}
