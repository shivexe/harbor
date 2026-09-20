import AppKit
import Foundation
import Darwin
import SwiftTerm
import SwiftUI

struct HostKeyCandidate: Identifiable {
    let id = UUID()
    let host: Host
    let records: String
    let fingerprints: String
}

struct SSH {
    static func configPath(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "%", with: "%%")
        return "\"\(escaped)\""
    }

    static func capture(_ executable: String, _ arguments: [String]) async throws -> Data {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + 12) {
                if process.isRunning { process.terminate() }
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, !data.isEmpty else { throw HarborError.message("Could not retrieve the host key. Check the address, port and network connection.") }
            return data
        }.value
    }

    static func inspect(_ host: Host) async throws -> HostKeyCandidate {
        try host.validate()
        let scanned = try await capture("/usr/bin/ssh-keyscan", ["-T", "8", "-p", String(host.port), host.address])
        guard let records = String(data: scanned, encoding: .utf8), records.count < 65536 else { throw HarborError.message("The host returned an invalid host key.") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try scanned.write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }
        let fingerprints = try await capture("/usr/bin/ssh-keygen", ["-l", "-E", "sha256", "-f", file.path])
        guard let text = String(data: fingerprints, encoding: .utf8) else { throw HarborError.message("Could not fingerprint the host key.") }
        return HostKeyCandidate(host: host, records: records, fingerprints: text)
    }
}

enum ConnectionPhase: Int {
    case connecting, verifying, authenticating, openingShell, ready, failed, ended

    var title: String {
        switch self {
        case .connecting: return "Connecting to server"
        case .verifying: return "Verifying server key"
        case .authenticating: return "Authenticating"
        case .openingShell: return "Opening shell"
        case .ready: return "Session open"
        case .failed: return "Connection failed"
        case .ended: return "Session ended"
        }
    }
}

struct SSHDiagnosticParser {
    private(set) var phase = ConnectionPhase.connecting
    private(set) var failureHint: String?

    mutating func consume(_ line: String) {
        let line = line.trimmingCharacters(in: .newlines)
        if line == "debug1: Connection established.", phase == .connecting { phase = .verifying }
        if line.hasPrefix("debug1: Host '") && line.contains(" is known and matches the ") && line.hasSuffix(" host key."), phase == .verifying { phase = .authenticating }
        if line.hasPrefix("Authenticated to ") && line.contains(" using \""), phase == .authenticating { phase = .openingShell }
        if line.hasPrefix("debug2: shell request accepted on channel "), phase == .openingShell { phase = .ready }
        if line.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") || line.contains("Host key verification failed") || line.contains(" host key is known for ") {
            failureHint = "The server key could not be verified. Check the saved fingerprint before trying again."
        } else if line.contains("Permission denied") {
            failureHint = "Authentication failed. Check the username and authentication method."
        } else if line.contains("Could not resolve hostname") {
            failureHint = "The hostname could not be resolved. Check the address and network."
        } else if line.contains("Connection refused") {
            failureHint = "The server refused the connection. Check its address, port and SSH service."
        } else if line.contains("Connection timed out") || line.contains("Operation timed out") {
            failureHint = "The connection timed out. Check the address, port and network."
        }
    }
}

@MainActor
final class TerminalSession: NSObject, ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let host: Host
    let terminal: LocalProcessTerminalView
    private let bridge: TerminalBridge
    @Published private(set) var phase = ConnectionPhase.connecting
    @Published private(set) var failure: String?
    var status: String { phase.title }
    var lastMilestone: ConnectionPhase { diagnostics.phase }
    private let directory: URL
    private let reference = UUID().uuidString
    private var credentialStored = false
    private var cleaned = false
    private var diagnostics = SSHDiagnosticParser()
    private var diagnosticBuffer = Data()
    private var diagnosticReader: Int32 = -1
    private var diagnosticWriter: Int32 = -1
    private var diagnosticSource: DispatchSourceRead?
    private var deadline: DispatchWorkItem?

    init(host: Host, root: URL) throws {
        try host.validate()
        guard !host.knownHosts.isEmpty else { throw HarborError.message("Verify this host’s fingerprint before connecting.") }
        self.host = host
        directory = root.appendingPathComponent("Sessions", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        terminal = LocalProcessTerminalView(frame: .zero)
        bridge = TerminalBridge(terminal: terminal)
        super.init()
        do {
            try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let knownHosts = directory.appendingPathComponent("known_hosts")
            try Self.writeRestricted(Data(host.knownHosts.utf8), to: knownHosts)
            let diagnosticPath = directory.appendingPathComponent("ssh-diagnostics")
            try startDiagnostics(at: diagnosticPath)
            var arguments = ["-F", "/dev/null", "-vv", "-E", diagnosticPath.path, "-tt", "-p", String(host.port), "-l", host.username,
                             "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=\(SSH.configPath(knownHosts.path))",
                             "-o", "GlobalKnownHostsFile=/dev/null", "-o", "ConnectTimeout=12",
                             "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3",
                             "-o", "PermitLocalCommand=no", "-o", "ForwardAgent=no", "-o", "ForwardX11=no",
                             "-o", "NumberOfPasswordPrompts=1", "-o", "IdentityAgent=none"]
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "SSH_ASKPASS")
            environment.removeValue(forKey: "SSH_ASKPASS_REQUIRE")
            environment.removeValue(forKey: "HARBOR_ASKPASS_REFERENCE")
            environment["TERM"] = "xterm-256color"
            environment["LC_CTYPE"] = "UTF-8"
            environment.removeValue(forKey: "LC_ALL")
            environment["LC_MESSAGES"] = "C"
            if host.auth == .key {
                let key = directory.appendingPathComponent("identity")
                try Self.writeRestricted(Data(host.privateKey.utf8), to: key)
                arguments += ["-i", key.path, "-o", "IdentitiesOnly=yes", "-o", "PreferredAuthentications=publickey"]
            }
            if host.auth == .password { arguments += ["-o", "PubkeyAuthentication=no", "-o", "PreferredAuthentications=password,keyboard-interactive"] }
            if host.auth == .none {
                arguments += ["-o", "BatchMode=yes", "-o", "PreferredAuthentications=none",
                              "-o", "PubkeyAuthentication=no", "-o", "PasswordAuthentication=no",
                              "-o", "KbdInteractiveAuthentication=no", "-o", "GSSAPIAuthentication=no",
                              "-o", "HostbasedAuthentication=no", "-o", "IdentitiesOnly=yes"]
            }
            if host.auth != .none && !host.secret.isEmpty {
                let helper = Keychain.helperURL
                guard !host.secret.contains("\n"), !host.secret.contains("\r"), FileManager.default.isExecutableFile(atPath: helper.path) else { throw HarborError.message("The credential helper is missing or the credential contains a line break.") }
                try Keychain.put(Data(host.secret.utf8), account: "askpass-\(reference)")
                credentialStored = true
                environment["SSH_ASKPASS"] = helper.path
                environment["SSH_ASKPASS_REQUIRE"] = "force"
                environment["HARBOR_ASKPASS_REFERENCE"] = reference
                environment["DISPLAY"] = "harbor:0"
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [reference] in Keychain.remove("askpass-\(reference)") }
            }
            arguments += ["--", host.address]
            terminal.processDelegate = self
            terminal.terminalDelegate = bridge
            terminal.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            terminal.nativeBackgroundColor = NSColor(srgbRed: 23.0 / 255, green: 25.0 / 255, blue: 31.0 / 255, alpha: 1)
            terminal.nativeForegroundColor = NSColor(srgbRed: 241.0 / 255, green: 242.0 / 255, blue: 246.0 / 255, alpha: 1)
            terminal.startProcess(executable: "/usr/bin/ssh", args: arguments, environment: environment.map { "\($0.key)=\($0.value)" })
            guard terminal.process.running else { throw HarborError.message("OpenSSH could not start. Close unused sessions and try again.") }
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.cleaned, self.phase.rawValue < ConnectionPhase.ready.rawValue else { return }
                self.failure = "SSH did not open a shell in time. Check the network or authentication method, then retry."
                self.phase = .failed
                self.terminal.terminate()
                self.cleanup()
            }
            deadline = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: work)
        } catch {
            cleanup()
            throw error
        }
    }

    private static func writeRestricted(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw HarborError.message("Could not create a protected session file.") }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try file.write(contentsOf: data)
        try file.close()
    }

    private func startDiagnostics(at url: URL) throws {
        guard mkfifo(url.path, 0o600) == 0 else { throw HarborError.message("Could not create a protected SSH diagnostic stream.") }
        let reader = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard reader >= 0 else { throw HarborError.message("Could not open the SSH diagnostic stream.") }
        let writer = open(url.path, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
        guard writer >= 0 else {
            Darwin.close(reader)
            throw HarborError.message("Could not keep the SSH diagnostic stream open.")
        }
        diagnosticReader = reader
        diagnosticWriter = writer
        let source = DispatchSource.makeReadSource(fileDescriptor: reader, queue: .main)
        source.setEventHandler { [weak self] in self?.readDiagnostics() }
        source.setCancelHandler { Darwin.close(reader) }
        diagnosticSource = source
        source.resume()
    }

    private func readDiagnostics() {
        guard diagnosticReader >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 4096)
        for _ in 0..<4 {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(diagnosticReader, $0.baseAddress, $0.count) }
            guard count > 0 else { break }
            diagnosticBuffer.append(contentsOf: bytes.prefix(count))
            while let newline = diagnosticBuffer.firstIndex(of: 10) {
                let line = String(decoding: diagnosticBuffer[..<newline], as: UTF8.self).trimmingCharacters(in: .newlines)
                diagnosticBuffer.removeSubrange(...newline)
                diagnostics.consume(line)
                if phase.rawValue < ConnectionPhase.ready.rawValue, diagnostics.phase.rawValue > phase.rawValue {
                    phase = diagnostics.phase
                    if phase == .ready { deadline?.cancel(); deadline = nil }
                }
            }
            if diagnosticBuffer.count > 8192 { diagnosticBuffer.removeFirst(diagnosticBuffer.count - 8192) }
            if count < bytes.count { break }
        }
    }

    func close() {
        terminal.terminate()
        cleanup()
        phase = .ended
    }

    private func cleanup() {
        guard !cleaned else { return }
        cleaned = true
        deadline?.cancel()
        deadline = nil
        diagnosticSource?.cancel()
        diagnosticSource = nil
        diagnosticReader = -1
        if diagnosticWriter >= 0 { Darwin.close(diagnosticWriter); diagnosticWriter = -1 }
        if credentialStored { Keychain.remove("askpass-\(reference)") }
        try? FileManager.default.removeItem(at: directory)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard !cleaned else { return }
        readDiagnostics()
        if phase != .ready && phase != .failed {
            failure = diagnostics.failureHint ?? "SSH ended before opening a shell. Check the host configuration and try again."
            phase = .failed
        } else if phase == .ready { phase = .ended }
        cleanup()
    }
}

struct TerminalSurface: NSViewRepresentable {
    let session: TerminalSession
    let active: Bool
    final class Coordinator { var active = false }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> LocalProcessTerminalView { session.terminal }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        guard active != context.coordinator.active else { return }
        context.coordinator.active = active
        if active { DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) } }
    }
}

@MainActor
final class TerminalBridge: TerminalViewDelegate {
    private weak var terminal: LocalProcessTerminalView?
    init(terminal: LocalProcessTerminalView) { self.terminal = terminal }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { terminal?.sizeChanged(source: source, newCols: newCols, newRows: newRows) }
    func setTerminalTitle(source: TerminalView, title: String) { terminal?.setTerminalTitle(source: source, title: title) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { terminal?.hostCurrentDirectoryUpdate(source: source, directory: directory) }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { terminal?.send(source: source, data: data) }
    func scrolled(source: TerminalView, position: Double) { terminal?.scrolled(source: source, position: position) }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) { terminal?.rangeChanged(source: source, startY: startY, endY: endY) }
    func clipboardCopy(source: TerminalView, content: Data) {}
    func clipboardRead(source: TerminalView) -> Data? { nil }
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }
}
