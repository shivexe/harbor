import AppKit
import SwiftUI

struct HostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LibraryStore
    @State var host: Host
    @State private var error: String?

    init(host: Host, store: LibraryStore) {
        self.store = store
        _host = State(initialValue: host)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(store.library.hosts.contains(where: { $0.id == host.id }) ? "Edit host" : "New host").font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: "server.rack").foregroundStyle(Palette.accent).font(.system(size: 24))
            }
            Form {
                TextField("Name", text: $host.name)
                TextField("Hostname or IP", text: $host.address)
                TextField("Port", value: $host.port, formatter: portFormatter)
                TextField("Username", text: $host.username)
                TextField("Group", text: $host.group)
                Picker("Authentication", selection: $host.auth) {
                    ForEach(Host.Authentication.allCases, id: \.self) { method in Text(method.label).tag(method) }
                }
                .onChange(of: host.auth) { _, method in
                    host.secret = ""
                    if method == .password { host.privateKey = "" }
                }
                if host.auth == .password {
                    SecureField("Password", text: $host.secret)
                } else {
                    HStack {
                        Text("Private key")
                        Spacer()
                        Text(host.privateKey.isEmpty ? "No key imported" : "Key imported").foregroundStyle(.secondary)
                        Button("Import key…") { importKey() }
                    }
                    SecureField("Passphrase (optional)", text: $host.secret)
                }
                TextField("Notes", text: $host.notes, axis: .vertical).lineLimit(3...5)
            }.formStyle(.grouped).scrollDisabled(true)
            Text("Credentials are encrypted on this Mac. Changes reach paired devices when they sync.").font(.system(size: 12)).foregroundStyle(.secondary)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red).accessibilityLabel("Error: \(error)") }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save host") {
                    do { try store.save(host); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 560).background(Palette.sidebar).tint(Palette.accent)
    }

    private var portFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 65535
        return formatter
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
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "checkmark.shield").font(.system(size: 32)).foregroundStyle(Palette.accent)
            Text("Verify \(candidate.host.name)").font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("Compare these fingerprints with a trusted source, such as your server console or administrator. A network scan alone cannot confirm the server’s identity.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Text(candidate.fingerprints.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(16)
                .frame(maxWidth: .infinity, alignment: .leading).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
            Toggle("I compared the fingerprints with a trusted source", isOn: $verified)
            if let error { Text(error).foregroundStyle(.red).font(.system(size: 12)) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Trust and connect") {
                    do { try store.trust(candidate); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(!verified)
            }
        }.padding(30).frame(width: 640).background(Palette.sidebar).tint(Palette.accent)
    }
}
