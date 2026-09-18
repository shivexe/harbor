import CryptoKit
import Foundation
import Security

struct Envelope: Codable {
    var nonce: String
    var ciphertext: String
    var tag: String
    var deviceId: String?
}

struct SyncCrypto {
    static func random(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        precondition(SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess)
        return Data(bytes)
    }

    static func seal<T: Encodable>(_ value: T, key: Data, aad: String) throws -> Envelope {
        guard key.count == 32 else { throw HarborError.message("Invalid encryption key.") }
        let box = try AES.GCM.seal(JSONEncoder().encode(value), using: SymmetricKey(data: key), authenticating: Data(aad.utf8))
        return Envelope(nonce: box.nonce.withUnsafeBytes { Data($0).base64EncodedString() }, ciphertext: box.ciphertext.base64EncodedString(), tag: box.tag.base64EncodedString())
    }

    static func open<T: Decodable>(_ type: T.Type, envelope: Envelope, key: Data, aad: String) throws -> T {
        guard key.count == 32, let nonce = Data(base64Encoded: envelope.nonce), nonce.count == 12,
              let ciphertext = Data(base64Encoded: envelope.ciphertext), ciphertext.count <= 16 * 1024 * 1024,
              let tag = Data(base64Encoded: envelope.tag), tag.count == 16 else { throw HarborError.message("Invalid encrypted message.") }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
        let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(aad.utf8))
        return try JSONDecoder().decode(type, from: plaintext)
    }

    static func comparison(secret: Data, nonce: Data) -> String {
        let digest = SHA256.hash(data: secret + nonce)
        let number = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06u", number % 1_000_000)
    }
}

struct WireHost: Codable {
    let id: String
    let name: String
    let hostname: String
    let port: Int
    let username: String
    let group: String
    let authType: String
    let password: String
    let privateKey: String
    let passphrase: String
    let hostKey: String
    let notes: String

    init(_ host: Host) {
        id = host.id
        name = host.name
        hostname = host.address
        port = host.port
        username = host.username
        group = host.group
        authType = host.auth.rawValue
        password = host.auth == .password ? host.secret : ""
        privateKey = host.auth == .key ? host.privateKey : ""
        passphrase = host.auth == .key ? host.secret : ""
        notes = host.notes
        let keys = host.knownHosts.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }.filter { $0.count >= 3 }
        let selected = keys.first(where: { $0[1] == "ssh-ed25519" }) ?? keys.first
        hostKey = selected.map { "\($0[1]) \($0[2])" } ?? ""
    }
}

struct Snapshot: Codable {
    var version = 1
    let vaultId: String
    let revision: Int64
    let generatedAt: Int64
    let requestId: String
    let hosts: [WireHost]
}

struct SignedSnapshot: Codable {
    let payload: String
    let signature: String
}
