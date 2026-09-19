import CryptoKit
import Foundation
import Darwin
import LocalAuthentication
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var library = Library()
    @Published var error: String?
    @Published var sessions: [TerminalSession] = []
    @Published var activeSession: UUID?
    @Published var loaded = false
    @Published private(set) var authenticating = false
    private var authentication: LAContext?
    private var lockGeneration: UInt64 = 0
    private(set) var vault: Vault?
    var onLock: (() -> Void)?
    private var lockDescriptor: Int32 = -1

    init() {}

    #if DEBUG
    init(testVault: Vault, library: Library) {
        vault = testVault
        self.library = library
        loaded = true
    }
    #endif

    private func claimLibrary() throws {
        guard lockDescriptor == -1 else { return }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Harbor", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let descriptor = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw HarborError.message("Could not acquire your library lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw HarborError.message("Harbor is already running. Close the other instance before opening this library.")
        }
        lockDescriptor = descriptor
    }

    func lock() {
        lockGeneration &+= 1
        authentication?.invalidate()
        authentication = nil
        onLock?()
        guard loaded else { return }
        closeAll()
        sessions.removeAll()
        activeSession = nil
        library = Library()
        vault = nil
        loaded = false
    }

    func unlock() async {
        guard !authenticating, !loaded else { return }
        authenticating = true
        let generation = lockGeneration
        defer { authenticating = false; authentication = nil }
        do {
            let context = LAContext()
            authentication = context
            var failure: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &failure) else {
                throw HarborError.message(failure?.localizedDescription ?? "Enable device authentication in macOS to unlock Harbor.")
            }
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your encrypted Harbor host library"), generation == lockGeneration else { return }
            try claimLibrary()
            Keychain.removeTemporaryItems()
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Harbor", isDirectory: true)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("Sessions", isDirectory: true))
            let vault = try Vault()
            var library = try vault.load()
            if library.signingKey.isEmpty {
                library.signingKey = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
                try vault.save(library)
            }
            self.vault = vault
            self.library = library
            loaded = true
            error = nil
        } catch { if generation == lockGeneration { self.error = error.localizedDescription } }
    }

    func save(_ host: Host) throws {
        try host.validate()
        var next = library
        if let index = next.hosts.firstIndex(where: { $0.id == host.id }) {
            let old = next.hosts[index]
            var updated = host
            if old.address != host.address || old.port != host.port { updated.knownHosts = "" }
            next.hosts[index] = updated
        } else { next.hosts.append(host) }
        next.revision += 1
        try commit(next)
    }

    func delete(_ host: Host) {
        do {
            var next = library
            next.hosts.removeAll { $0.id == host.id }
            next.revision += 1
            try commit(next)
        } catch { self.error = error.localizedDescription }
    }

    func trust(_ candidate: HostKeyCandidate) throws {
        guard let index = library.hosts.firstIndex(where: { $0.id == candidate.host.id }), library.hosts[index].address == candidate.host.address, library.hosts[index].port == candidate.host.port else { throw HarborError.message("The host changed while its key was being verified. Try again.") }
        var next = library
        next.hosts[index].knownHosts = candidate.records
        next.revision += 1
        try commit(next)
        connect(next.hosts[index])
    }

    func connect(_ host: Host) {
        do {
            guard let vault else { throw HarborError.message("Your encrypted library is unavailable.") }
            let session = try TerminalSession(host: host, root: vault.directory)
            sessions.append(session)
            activeSession = session.id
        } catch { self.error = error.localizedDescription }
    }

    func close(_ session: TerminalSession) {
        session.close()
        sessions.removeAll { $0.id == session.id }
        if activeSession == session.id { activeSession = sessions.last?.id }
    }

    func closeAll() { sessions.forEach { $0.close() } }

    func commit(_ next: Library) throws {
        guard let vault else { throw HarborError.message("Your encrypted library is unavailable.") }
        guard next.revision >= 1, next.revision <= 9_007_199_254_740_991, next.hosts.count <= 10000, Set(next.hosts.map(\.id)).count == next.hosts.count else { throw HarborError.message("Your library exceeds the supported host limit.") }
        for host in next.hosts { try host.validate() }
        let bytes = try JSONEncoder().encode(next.hosts.map(WireHost.init))
        guard bytes.count < 8 * 1024 * 1024 - 4096 else { throw HarborError.message("Your host library exceeds the 8 MiB sync limit.") }
        try vault.save(next)
        library = next
    }
}
