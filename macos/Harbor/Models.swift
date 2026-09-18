import Foundation

struct Host: Codable, Identifiable, Equatable {
    var id = UUID().uuidString.lowercased()
    var name = ""
    var address = ""
    var port = 22
    var username = ""
    var group = ""
    var auth = Authentication.password
    var secret = ""
    var privateKey = ""
    var notes = ""
    var knownHosts = ""

    enum Authentication: String, Codable, CaseIterable {
        case password, key
        var label: String {
            switch self {
            case .password: return "Password"
            case .key: return "Private key"
            }
        }
    }

    func validate() throws {
        guard id == id.lowercased() && UUID(uuidString: id) != nil, privateKey.utf8.count <= 256 * 1024,
              try JSONEncoder().encode(self).count <= 1024 * 1024 else { throw HarborError.message("The host record exceeds the supported size or has an invalid identity.") }
        guard [name, group].allSatisfy({ $0.count <= 256 && $0.rangeOfCharacter(from: .controlCharacters) == nil }),
              address.count <= 253, username.count <= 128,
              !secret.contains("\n"), !secret.contains("\r") else { throw HarborError.message("Host fields contain unsupported characters or exceed the supported length.") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HarborError.message("Enter a host name.") }
        guard !address.isEmpty, !address.hasPrefix("-"), address.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              address.rangeOfCharacter(from: .controlCharacters) == nil,
              !address.contains("/"), !address.contains("@") else { throw HarborError.message("Enter a hostname or IP address without spaces.") }
        guard (1...65535).contains(port) else { throw HarborError.message("Port must be between 1 and 65535.") }
        guard !username.isEmpty, !username.hasPrefix("-"), username.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              username.rangeOfCharacter(from: .controlCharacters) == nil else { throw HarborError.message("Enter an SSH username without spaces.") }
        if auth == .key, !privateKey.contains("PRIVATE KEY") { throw HarborError.message("Import an SSH private key.") }
        if auth == .password, secret.isEmpty { throw HarborError.message("Enter a password.") }
    }
}

struct PairedDevice: Codable, Identifiable {
    var id: String
    var name: String
    var secret: String
    var pairedAt: Int64
}

struct Library: Codable {
    var revision: Int64 = 1
    var hosts: [Host] = []
    var devices: [PairedDevice] = []
    var desktopID = UUID().uuidString.lowercased()
    var signingKey = ""
}

enum HarborError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
