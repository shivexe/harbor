import AppKit
import Darwin
import SwiftUI

struct HarborFocusRing: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content.overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? Palette.focus : .clear, lineWidth: 2))
    }
}

struct HostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LibraryStore
    @State private var host: Host
    @State private var passwordDraft: String
    @State private var passphraseDraft: String
    @State private var portText: String
    @State private var moreOptions: Bool
    @State private var pasteEditorOpen = false
    @State private var error: String?
    @State private var saveID: UUID?
    private enum Field: Hashable { case address, username, password, passphrase, name, port, group, notes }
    @FocusState private var focusedField: Field?
    private let prepare: (Host, String, String, String) throws -> Host
    let onSaved: (Host) -> Void

    init(host: Host, store: LibraryStore, prepare: @escaping (Host, String, String, String) throws -> Host = {
        try HostEditor.preparedHost($0, portText: $1, password: $2, passphrase: $3)
    }, onSaved: @escaping (Host) -> Void = { _ in }) {
        self.store = store
        self.prepare = prepare
        self.onSaved = onSaved
        _host = State(initialValue: host)
        _passwordDraft = State(initialValue: host.auth == .password ? host.secret : "")
        _passphraseDraft = State(initialValue: host.auth == .key ? host.secret : "")
        _portText = State(initialValue: String(host.port))
        _moreOptions = State(initialValue: (!host.name.isEmpty && host.name != host.address) || host.port != 22 || !host.group.isEmpty || !host.notes.isEmpty)
    }

    private var isEditing: Bool { store.library.hosts.contains { $0.id == host.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isEditing ? "Edit host" : "Add host").font(.system(size: 20, weight: .semibold))
                Spacer()
            }.padding(.horizontal, 24).frame(height: 52)
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Hostname or IP address").font(.system(size: 14, weight: .medium))
                        TextField("example.com", text: $host.address).textFieldStyle(.plain)
                            .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 34)
                            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                            .modifier(HarborFocusRing(active: focusedField == .address))
                            .focused($focusedField, equals: .address).accessibilityLabel("Hostname or IP address")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Port").font(.system(size: 14, weight: .medium))
                        TextField("22", text: $portText).textFieldStyle(.plain)
                            .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 34)
                            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                            .modifier(HarborFocusRing(active: focusedField == .port))
                            .focused($focusedField, equals: .port).accessibilityLabel("Port")
                    }.frame(width: 84)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Username").font(.system(size: 14, weight: .medium))
                        TextField("SSH username", text: $host.username).textFieldStyle(.plain)
                            .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 34)
                            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                            .modifier(HarborFocusRing(active: focusedField == .username))
                            .focused($focusedField, equals: .username)
                            .accessibilityLabel("Username")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Authentication").font(.system(size: 14, weight: .medium))
                        Picker("Authentication", selection: $host.auth) {
                            Text("No password").tag(Host.Authentication.none)
                            Text("Password").tag(Host.Authentication.password)
                            Text("Private key").tag(Host.Authentication.key)
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    if host.auth == .password {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Password").font(.system(size: 14, weight: .medium))
                            SecureField("SSH password", text: $passwordDraft).textFieldStyle(.plain)
                                .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 34)
                                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                                .modifier(HarborFocusRing(active: focusedField == .password))
                                .focused($focusedField, equals: .password)
                                .accessibilityLabel("Password")
                        }
                    } else if host.auth == .key {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Private key").font(.system(size: 14, weight: .medium))
                            HStack(spacing: 12) {
                                Image(systemName: host.privateKey.isEmpty ? "key" : "checkmark.shield")
                                    .foregroundStyle(Palette.accent)
                                Text(host.privateKey.isEmpty ? "No private key" : "Private key added")
                                    .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                                Spacer()
                                Button("Import file…") { importKey() }
                                Button("Paste key…") { pasteEditorOpen = true }
                            }.padding(.horizontal, 10).frame(height: 38)
                                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Key passphrase").font(.system(size: 14, weight: .medium))
                            SecureField("Optional", text: $passphraseDraft).textFieldStyle(.plain)
                                .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 34)
                                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                                .modifier(HarborFocusRing(active: focusedField == .passphrase))
                                .focused($focusedField, equals: .passphrase)
                                .accessibilityLabel("Key passphrase")
                        }
                    } else {
                        Text("Use this when Tailscale SSH is enabled on the destination. Harbor still verifies the server fingerprint before connecting.")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Button {
                        moreOptions.toggle()
                        if moreOptions {
                            DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.18)) { scroll.scrollTo("advanced", anchor: .top) } }
                        }
                    } label: {
                        HStack {
                            Text("More options")
                            Spacer()
                            Image(systemName: moreOptions ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                        }.font(.system(size: 13, weight: .medium)).frame(height: 36)
                            .padding(.horizontal, 10).contentShape(Rectangle())
                            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).accessibilityLabel("More options")
                        .accessibilityValue(moreOptions ? "Expanded" : "Collapsed")
                    if moreOptions {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Display name").font(.system(size: 14, weight: .medium))
                                TextField("Uses hostname if empty", text: $host.name).textFieldStyle(.plain)
                                    .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 34)
                                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                                    .modifier(HarborFocusRing(active: focusedField == .name))
                                    .focused($focusedField, equals: .name)
                                    .accessibilityLabel("Display name")
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Group").font(.system(size: 14, weight: .medium))
                                TextField("Optional", text: $host.group).textFieldStyle(.plain)
                                    .font(.system(size: 13)).padding(.horizontal, 10).frame(height: 34)
                                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                                    .modifier(HarborFocusRing(active: focusedField == .group))
                                    .focused($focusedField, equals: .group)
                                    .accessibilityLabel("Group")
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Notes").font(.system(size: 14, weight: .medium))
                                TextField("Optional", text: $host.notes, axis: .vertical).lineLimit(3...5)
                                    .textFieldStyle(.plain).font(.system(size: 13)).padding(10)
                                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                                    .modifier(HarborFocusRing(active: focusedField == .notes))
                                    .focused($focusedField, equals: .notes)
                                    .accessibilityLabel("Notes")
                            }
                        }.id("advanced")
                    }
                    Text(host.auth == .none ? "No SSH credential stored." : "Credentials are encrypted on this Mac and synced to paired devices.")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            }.disabled(saveID != nil)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let error {
                    Text(error).font(.system(size: 12)).foregroundStyle(.red)
                        .accessibilityLabel("Error: \(error)")
                }
                HStack {
                    Spacer()
                    Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction).controlSize(.large)
                    Button { save() } label: {
                        HStack(spacing: 6) {
                            if saveID != nil { ProgressView().controlSize(.small) }
                            Text(saveID == nil ? "Save host" : "Validating…")
                        }
                    }.buttonStyle(HarborActionStyle()).keyboardShortcut(.defaultAction).disabled(saveID != nil)
                }
            }.padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(width: 560, height: 540).background(Palette.canvas)
            .tint(Palette.accent).foregroundStyle(Palette.text)
            .sheet(isPresented: $pasteEditorOpen) { KeyPasteView { host.privateKey = $0; error = nil } }
            .onDisappear { saveID = nil }
            .task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if !isEditing && focusedField == nil { focusedField = .address }
            }
    }

    private func save() {
        guard saveID == nil else { return }
        let id = UUID()
        saveID = id
        error = nil
        let draft = host
        let port = portText
        let password = passwordDraft
        let passphrase = passphraseDraft
        let prepare = prepare
        Task {
            do {
                let saved = try await Task.detached(priority: .userInitiated) {
                    try prepare(draft, port, password, passphrase)
                }.value
                guard saveID == id else { return }
                guard store.loaded else { saveID = nil; return }
                try store.save(saved)
                saveID = nil
                onSaved(saved)
                dismiss()
            } catch {
                guard saveID == id else { return }
                saveID = nil
                self.error = error.localizedDescription
            }
        }
    }

    private func cancel() {
        saveID = nil
        dismiss()
    }

    static func preparedHost(_ host: Host, portText: String, password: String, passphrase: String) throws -> Host {
        guard let port = Int(portText), (1...65535).contains(port) else {
            throw HarborError.message("Port must be between 1 and 65535.")
        }
        var saved = host
        saved.address = saved.address.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.name.isEmpty { saved.name = saved.address }
        saved.port = port
        saved.secret = saved.auth == .password ? password : saved.auth == .key ? passphrase : ""
        if saved.auth == .key { saved.privateKey = try PrivateKeyValidator.validate(saved.privateKey, passphrase: passphrase) }
        else { saved.privateKey = "" }
        return saved
    }

    private func importKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an OpenSSH or PEM private key. Harbor saves an encrypted copy."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 256 * 1024 else { throw HarborError.message("Choose a private key smaller than 256 KiB.") }
            host.privateKey = try PrivateKeyValidator.validate(String(contentsOf: url, encoding: .utf8))
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct KeyPasteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var error: String?
    @FocusState private var keyFocused: Bool
    let save: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Paste private key").font(.system(size: 20, weight: .semibold))
                .padding(.horizontal, 24).frame(height: 52, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste an OpenSSH or PEM private key. The previous key stays in place until you confirm.")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                TextEditor(text: $draft).font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(10)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Private key text")
                    .focused($keyFocused)
                Text("OpenSSH or PEM private key, up to 256 KiB.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            }.padding(24)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { draft = ""; dismiss() }.keyboardShortcut(.cancelAction)
                Button("Use key") {
                    do {
                        save(try PrivateKeyValidator.validate(draft))
                        draft = ""
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(HarborActionStyle()).keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(width: 580, height: 460).background(Palette.canvas)
            .tint(Palette.accent).foregroundStyle(Palette.text)
            .task { keyFocused = true }
            .onDisappear { draft = "" }
    }
}

struct PrivateKeyValidator {
    static func validate(_ value: String, passphrase: String? = nil) throws -> String {
        let bytes = value.utf8.count
        guard bytes > 0, bytes <= 256 * 1024 else { throw HarborError.message("This key is larger than 256 KiB or empty.") }
        let text = value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains("\0"), !text.hasPrefix("PuTTY-User-Key-File"), !text.contains("BEGIN PUBLIC KEY"), !text.hasPrefix("ssh-") else {
            throw HarborError.message("Choose an OpenSSH or PEM private key, not a public key or PuTTY file.")
        }
        let labels = ["OPENSSH PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY", "DSA PRIVATE KEY", "PRIVATE KEY", "ENCRYPTED PRIVATE KEY"]
        guard let label = labels.first(where: { text.hasPrefix("-----BEGIN \($0)-----\n") }),
              text.hasSuffix("-----END \(label)-----") else {
            throw HarborError.message("Choose an OpenSSH or PEM private key, not a public key or PuTTY file.")
        }
        let body = text.dropFirst("-----BEGIN \(label)-----\n".count).dropLast("-----END \(label)-----".count)
        let lines = body.split(whereSeparator: \.isNewline).map(String.init)
        let encoded = lines.filter { !$0.contains(":") }.joined()
        guard !encoded.isEmpty, encoded.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=") }),
              let decoded = Data(base64Encoded: encoded), decoded.count > 32 else {
            throw HarborError.message("This private key is incomplete or invalid. Export it again and retry.")
        }
        let traditionalEncrypted = body.contains("Proc-Type: 4,ENCRYPTED")
        let encryptedPEM = label == "ENCRYPTED PRIVATE KEY" || traditionalEncrypted
        let encryptedOpenSSH: Bool
        if label == "OPENSSH PRIVATE KEY" { encryptedOpenSSH = try validateOpenSSH(decoded) }
        else {
            encryptedOpenSSH = false
            if !traditionalEncrypted { try validateDER(decoded) }
        }
        if encryptedPEM, passphrase == nil { return text + "\n" }
        let passphraseInput: Data?
        if encryptedPEM {
            guard let passphrase, !passphrase.isEmpty else { throw HarborError.message("This private key is encrypted. Enter its passphrase.") }
            guard passphrase.utf8.count <= 4096, !passphrase.contains("\0"), !passphrase.contains("\n"), !passphrase.contains("\r") else {
                throw HarborError.message("The private key passphrase must be at most 4096 UTF-8 bytes and cannot contain NUL or line break characters.")
            }
            passphraseInput = Data((passphrase + "\n").utf8)
        } else { passphraseInput = nil }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Harbor-Key-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("identity")
        let descriptor = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw HarborError.message("Could not validate the private key securely.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: Data((text + "\n").utf8))
        try handle.close()
        if encryptedPEM {
            guard check(executable: "/usr/bin/openssl", arguments: ["pkey", "-in", file.path, "-passin", "stdin", "-noout"], input: passphraseInput) else {
                throw HarborError.message("The private key passphrase is incorrect, or the encrypted key is damaged.")
            }
        } else {
            guard check(executable: "/usr/bin/ssh-keygen", arguments: ["-l", "-f", file.path]),
                  encryptedOpenSSH || check(executable: "/usr/bin/ssh-keygen", arguments: ["-y", "-f", file.path]) else {
                throw HarborError.message("This private key is incomplete or invalid. Export it again and retry.")
            }
        }
        return text + "\n"
    }

    private static func check(executable: String, arguments: [String], input: Data? = nil) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = input == nil ? nil : Pipe()
        if let pipe { process.standardInput = pipe }
        else { process.standardInput = FileHandle.nullDevice }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "SSH_ASKPASS")
        environment.removeValue(forKey: "DISPLAY")
        environment["SSH_ASKPASS_REQUIRE"] = "never"
        process.environment = environment
        do {
            if let input, let pipe {
                try pipe.fileHandleForWriting.write(contentsOf: input)
                try pipe.fileHandleForWriting.close()
            }
            try process.run()
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning && Date() < deadline { usleep(10_000) }
            let timedOut = process.isRunning
            if timedOut {
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < terminationDeadline { usleep(10_000) }
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            return !timedOut && process.terminationStatus == 0
        } catch {
            try? pipe?.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            return false
        }
    }

    private static func validateOpenSSH(_ data: Data) throws -> Bool {
        let magic = Data("openssh-key-v1\0".utf8)
        var offset = magic.count
        guard data.starts(with: magic), let cipher = readString(data, offset: &offset),
              let kdf = readString(data, offset: &offset), let options = readString(data, offset: &offset),
              let count = readWord(data, offset: &offset), count == 1,
              let publicKey = readString(data, offset: &offset), !publicKey.isEmpty,
              let privateBlock = readString(data, offset: &offset), privateBlock.count >= 16,
              offset == data.count else {
            throw HarborError.message("This private key is incomplete or invalid. Export it again and retry.")
        }
        let encrypted = cipher != Data("none".utf8)
        guard encrypted ? !kdf.isEmpty : kdf == Data("none".utf8) && options.isEmpty else {
            throw HarborError.message("This private key is incomplete or invalid. Export it again and retry.")
        }
        return encrypted
    }

    private static func readWord(_ data: Data, offset: inout Int) -> Int? {
        guard offset + 4 <= data.count else { return nil }
        let value = data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        offset += 4
        return value
    }

    private static func readString(_ data: Data, offset: inout Int) -> Data? {
        guard let length = readWord(data, offset: &offset), length <= data.count - offset else { return nil }
        defer { offset += length }
        return data[offset..<(offset + length)]
    }

    private static func validateDER(_ data: Data) throws {
        guard data.count > 2, data[0] == 0x30 else { throw HarborError.message("This private key is incomplete or invalid. Export it again and retry.") }
        let count = Int(data[1] & 0x7f)
        let header: Int
        let length: Int
        if data[1] & 0x80 == 0 { header = 2; length = Int(data[1]) }
        else {
            guard count > 0, count <= 4, data.count >= 2 + count else { throw HarborError.message("This private key is incomplete or invalid. Export it again and retry.") }
            header = 2 + count
            length = data[2..<header].reduce(0) { ($0 << 8) | Int($1) }
        }
        guard header + length == data.count else { throw HarborError.message("This private key is incomplete or invalid. Export it again and retry.") }
    }
}

struct HostTrustView: View {
    @Environment(\.dismiss) private var dismiss
    let candidate: HostKeyCandidate
    @ObservedObject var store: LibraryStore
    @State private var verified = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "checkmark.shield").font(.system(size: 30)).foregroundStyle(Palette.accent)
                Text("Verify \(candidate.host.name)").font(.system(size: 28, weight: .semibold))
                Text("Compare these fingerprints with your server console or administrator before trusting this server.")
                    .font(.system(size: 14)).foregroundStyle(Palette.secondary)
            }.padding(32)
            Text(candidate.fingerprints.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 32)
            Toggle("I compared these fingerprints with a trusted source", isOn: $verified)
                .font(.system(size: 14)).padding(32)
            Spacer(minLength: 0)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if let error { Text(error).foregroundStyle(.red).font(.system(size: 12)) }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
                    Button("Trust and connect") {
                        do { try store.trust(candidate); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.buttonStyle(HarborActionStyle()).disabled(!verified)
                }
            }.padding(.horizontal, 32).padding(.vertical, 18)
        }.frame(width: 640, height: 460).background(Palette.sidebar)
            .tint(Palette.accent).foregroundStyle(Palette.text)
    }
}
