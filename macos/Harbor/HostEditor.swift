import AppKit
import SwiftUI

struct HarborFocusRing: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content.overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Palette.accent : .clear, lineWidth: 2))
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
    @State private var error: String?
    private enum Field: Hashable { case address, username, password, passphrase, name, port, group, notes }
    @FocusState private var focusedField: Field?
    let onSaved: (Host) -> Void

    init(host: Host, store: LibraryStore, onSaved: @escaping (Host) -> Void = { _ in }) {
        self.store = store
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
            VStack(alignment: .leading, spacing: 6) {
                Text(isEditing ? "Edit host" : "Add a host").font(.system(size: 28, weight: .semibold))
                Text("Enter the details you use to connect over SSH.")
                    .font(.system(size: 14)).foregroundStyle(Palette.secondary)
            }.padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hostname or IP address").font(.system(size: 14, weight: .medium))
                        TextField("example.com", text: $host.address).textFieldStyle(.plain)
                            .font(.system(size: 14)).padding(12).frame(height: 42)
                            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                            .modifier(HarborFocusRing(active: focusedField == .address))
                            .focused($focusedField, equals: .address).accessibilityLabel("Hostname or IP address")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username").font(.system(size: 14, weight: .medium))
                        TextField("SSH username", text: $host.username).textFieldStyle(.plain)
                            .font(.system(size: 14)).padding(12).frame(height: 42)
                            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                            .modifier(HarborFocusRing(active: focusedField == .username))
                            .focused($focusedField, equals: .username)
                            .accessibilityLabel("Username")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Authentication").font(.system(size: 14, weight: .medium))
                        Picker("Authentication", selection: $host.auth) {
                            ForEach(Host.Authentication.allCases, id: \.self) { method in Text(method.label).tag(method) }
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    if host.auth == .password {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password").font(.system(size: 14, weight: .medium))
                            SecureField("SSH password", text: $passwordDraft).textFieldStyle(.plain)
                                .font(.system(size: 14)).padding(12).frame(height: 42)
                                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                                .modifier(HarborFocusRing(active: focusedField == .password))
                                .focused($focusedField, equals: .password)
                                .accessibilityLabel("Password")
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Private key").font(.system(size: 14, weight: .medium))
                            HStack(spacing: 12) {
                                Image(systemName: host.privateKey.isEmpty ? "key" : "checkmark.shield")
                                    .foregroundStyle(Palette.accent)
                                Text(host.privateKey.isEmpty ? "No key imported" : "Key imported")
                                    .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                                Spacer()
                                Button("Import key…") { importKey() }.controlSize(.large)
                            }.padding(.horizontal, 12).frame(height: 44)
                                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Key passphrase").font(.system(size: 14, weight: .medium))
                            SecureField("Optional", text: $passphraseDraft).textFieldStyle(.plain)
                                .font(.system(size: 14)).padding(12).frame(height: 42)
                                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                                .modifier(HarborFocusRing(active: focusedField == .passphrase))
                                .focused($focusedField, equals: .passphrase)
                                .accessibilityLabel("Key passphrase")
                        }
                    }
                    DisclosureGroup(isExpanded: $moreOptions) {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Display name").font(.system(size: 14, weight: .medium))
                                TextField("Uses hostname if empty", text: $host.name).textFieldStyle(.plain)
                                    .font(.system(size: 14)).padding(12).frame(height: 42)
                                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                                    .modifier(HarborFocusRing(active: focusedField == .name))
                                    .focused($focusedField, equals: .name)
                                    .accessibilityLabel("Display name")
                            }
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Port").font(.system(size: 14, weight: .medium))
                                    TextField("22", text: $portText).textFieldStyle(.plain)
                                        .font(.system(size: 14)).padding(12).frame(height: 42)
                                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                                        .modifier(HarborFocusRing(active: focusedField == .port))
                                        .focused($focusedField, equals: .port)
                                        .accessibilityLabel("Port")
                                }.frame(width: 110)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Group").font(.system(size: 14, weight: .medium))
                                    TextField("Optional", text: $host.group).textFieldStyle(.plain)
                                        .font(.system(size: 14)).padding(12).frame(height: 42)
                                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                                        .modifier(HarborFocusRing(active: focusedField == .group))
                                        .focused($focusedField, equals: .group)
                                        .accessibilityLabel("Group")
                                }
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes").font(.system(size: 14, weight: .medium))
                                TextField("Optional", text: $host.notes, axis: .vertical).lineLimit(3...5)
                                    .textFieldStyle(.plain).font(.system(size: 14)).padding(12)
                                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                                    .modifier(HarborFocusRing(active: focusedField == .notes))
                                    .focused($focusedField, equals: .notes)
                                    .accessibilityLabel("Notes")
                            }
                        }.padding(.top, 16)
                    } label: {
                        Text("More options").font(.system(size: 14, weight: .medium))
                    }
                    .tint(Palette.accent)
                    Text("Credentials are encrypted on this Mac. Paired devices receive changes when they sync.")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    Text(error).font(.system(size: 12)).foregroundStyle(.red)
                        .accessibilityLabel("Error: \(error)")
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
                    Button("Save host") { save() }.buttonStyle(HarborActionStyle()).keyboardShortcut(.defaultAction)
                }
            }.padding(.horizontal, 32).padding(.vertical, 18)
        }.frame(width: 560, height: 650).background(Palette.sidebar)
            .tint(Palette.accent).foregroundStyle(Palette.text)
            .task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if !isEditing && focusedField == nil { focusedField = .address }
            }
    }

    private func save() {
        do {
            let saved = try Self.preparedHost(host, portText: portText, password: passwordDraft, passphrase: passphraseDraft)
            try store.save(saved)
            onSaved(saved)
            dismiss()
        } catch { self.error = error.localizedDescription }
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
        saved.secret = saved.auth == .password ? password : passphrase
        if saved.auth == .password { saved.privateKey = "" }
        return saved
    }

    private func importKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an OpenSSH or PEM private key. Harbor stores an encrypted copy."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 256 * 1024 else { throw HarborError.message("Choose a private key smaller than 256 KiB.") }
            let key = try String(contentsOf: url, encoding: .utf8)
            guard key.contains("PRIVATE KEY") else { throw HarborError.message("This file is not a supported private key.") }
            host.privateKey = key
            error = nil
        } catch { self.error = error.localizedDescription }
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
