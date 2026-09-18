import CryptoKit
import Foundation
import Security

struct Keychain {
    static let service = "app.harbor.desktop"
    static var helperURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/HarborAskPass") }

    static func read(_ account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw HarborError.message("Keychain access failed (\(status)).") }
        return data
    }

    static func put(_ data: Data, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            if account.hasPrefix("askpass-") {
                let helper = helperURL
                guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw HarborError.message("The credential helper is missing.") }
                var current: SecTrustedApplication?
                var executable: SecTrustedApplication?
                var access: SecAccess?
                guard SecTrustedApplicationCreateFromPath(nil, &current) == errSecSuccess,
                      SecTrustedApplicationCreateFromPath(helper.path, &executable) == errSecSuccess,
                      let current, let executable,
                      SecAccessCreate("Harbor SSH credential" as CFString, [current, executable] as CFArray, &access) == errSecSuccess,
                      let access else { throw HarborError.message("Could not authorize the credential helper.") }
                item[kSecAttrAccess as String] = access
            }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw HarborError.message("Could not save to Keychain (\(added)).") }
        } else if status != errSecSuccess { throw HarborError.message("Could not update Keychain (\(status)).") }
    }

    static func removeTemporaryItems() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return }
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String, account.hasPrefix("askpass-") { remove(account) }
        }
    }

    static func remove(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}

struct Vault {
    let directory: URL
    private let key: SymmetricKey
    var archive: URL { directory.appendingPathComponent("library.aesgcm") }

    init(directory: URL? = nil, key supplied: SymmetricKey? = nil) throws {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Harbor", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.directory.path)
        if let supplied { key = supplied }
        else if let saved = try Keychain.read("vault-master-v1") {
            guard saved.count == 32 else { throw HarborError.message("Your vault encryption key is invalid.") }
            key = SymmetricKey(data: saved)
        }
        else {
            guard !FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("library.aesgcm").path) else { throw HarborError.message("The library encryption key is missing. Restore the original Keychain before opening this library.") }
            let generated = SymmetricKey(size: .bits256)
            try Keychain.put(generated.withUnsafeBytes { Data($0) }, account: "vault-master-v1")
            key = generated
        }
    }

    func load() throws -> Library {
        guard FileManager.default.fileExists(atPath: archive.path) else { return Library() }
        let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 16 * 1024 * 1024 else { throw HarborError.message("Your encrypted library exceeds the supported size.") }
        let boxed = try AES.GCM.SealedBox(combined: Data(contentsOf: archive))
        let library = try JSONDecoder().decode(Library.self, from: AES.GCM.open(boxed, using: key, authenticating: Data("Harbor vault v1".utf8)))
        guard library.revision >= 1, library.revision <= 9_007_199_254_740_991, library.hosts.count <= 10000,
              Set(library.hosts.map(\.id)).count == library.hosts.count,
              let signing = Data(base64Encoded: library.signingKey), signing.count == 32,
              library.desktopID == library.desktopID.lowercased(), UUID(uuidString: library.desktopID) != nil,
              library.devices.count <= 100, Set(library.devices.map(\.id)).count == library.devices.count else { throw HarborError.message("Your encrypted library contains invalid records.") }
        for host in library.hosts { try host.validate() }
        for device in library.devices {
            guard device.id == device.id.lowercased(), UUID(uuidString: device.id) != nil,
                  !device.name.isEmpty, device.name.count <= 80,
                  let secret = Data(base64Encoded: device.secret), secret.count == 32 else { throw HarborError.message("Your encrypted library contains an invalid paired device.") }
        }
        return library
    }

    func save(_ library: Library) throws {
        let bytes = try JSONEncoder().encode(library)
        guard let sealed = try AES.GCM.seal(bytes, using: key, authenticating: Data("Harbor vault v1".utf8)).combined else { throw HarborError.message("Could not encrypt your library.") }
        try sealed.write(to: archive, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
    }
}
