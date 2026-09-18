import Foundation
import Security
import Darwin

var parentPath = [CChar](repeating: 0, count: 4096)
guard proc_pidpath(getppid(), &parentPath, UInt32(parentPath.count)) > 0,
      String(cString: parentPath) == "/usr/bin/ssh" else { exit(1) }
let environment = ProcessInfo.processInfo.environment
guard let reference = environment["HARBOR_ASKPASS_REFERENCE"], UUID(uuidString: reference) != nil else { exit(1) }
let prompt = CommandLine.arguments.dropFirst().joined(separator: " ").lowercased()
guard prompt.contains("password") || prompt.contains("passphrase") else { exit(1) }
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.harbor.desktop", kSecAttrAccount as String: "askpass-\(reference)", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
var result: CFTypeRef?
guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, !data.contains(10), !data.contains(13) else { exit(1) }
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([10]))
