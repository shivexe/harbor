import AppKit
import CryptoKit
import SwiftUI

struct Palette {
    static let canvas = Color(red: 36.0 / 255, green: 36.0 / 255, blue: 38.0 / 255)
    static let sidebar = Color(red: 28.0 / 255, green: 28.0 / 255, blue: 30.0 / 255)
    static let raised = Color(red: 48.0 / 255, green: 48.0 / 255, blue: 51.0 / 255)
    static let accent = Color(red: 64.0 / 255, green: 156.0 / 255, blue: 255.0 / 255)
    static let focus = Color(red: 10.0 / 255, green: 132.0 / 255, blue: 255.0 / 255)
    static let action = Color(red: 0.0 / 255, green: 104.0 / 255, blue: 217.0 / 255)
    static let text = Color(red: 242.0 / 255, green: 242.0 / 255, blue: 242.0 / 255)
    static let secondary = Color(red: 177.0 / 255, green: 177.0 / 255, blue: 182.0 / 255)
}

struct HarborActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(minHeight: 32)
            .background(Palette.action, in: RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct ContentView: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var sharing: SharingService
    @State private var query = ""
    @State private var selection: String?
    @State private var editor: Host?
    @State private var candidate: HostKeyCandidate?
    @State private var deleteHost: Host?
    @State private var showingSharing = false
    @State private var scanningHost: Host?
    @State private var scanError: String?
    @State private var scanToken = UUID()
    @FocusState private var searchFocused: Bool

    private var filtered: [Host] {
        store.library.hosts.filter { query.isEmpty || [$0.name, $0.address, $0.username, $0.group].contains(where: { $0.localizedCaseInsensitiveContains(query) }) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var groups: [String] { Set(filtered.map { $0.group.isEmpty ? "Ungrouped" : $0.group }).sorted() }
    private var selected: Host? { store.library.hosts.first { $0.id == selection } }
    private var active: TerminalSession? { store.sessions.first { $0.id == store.activeSession } }

    var body: some View {
        Group {
            if store.loaded {
                HSplitView {
                    sidebar.frame(minWidth: 220, idealWidth: 240, maxWidth: 275)
                    workspace.frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Harbor is locked").font(.system(size: 20, weight: .semibold))
                    Text("Unlock to use your hosts and paired devices.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    Button(store.authenticating ? "Unlocking…" : "Unlock Harbor") { Task { await store.unlock() } }
                        .buttonStyle(HarborActionStyle()).disabled(store.authenticating)
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.canvas)
        .tint(Palette.accent)
        .foregroundStyle(Palette.text)
        .sheet(item: $editor) { host in HostEditor(host: host, store: store, onSaved: { saved in query = ""; selection = saved.id; store.activeSession = nil }) }
        .sheet(item: $candidate) { value in HostTrustView(candidate: value, store: store) }
        .sheet(isPresented: $showingSharing, onDismiss: { sharing.dismissInvitation() }) { SharingView(store: store, sharing: sharing) }
        .alert("Harbor", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("Delete \(deleteHost?.name ?? "host")?", isPresented: Binding(get: { deleteHost != nil }, set: { if !$0 { deleteHost = nil } }), titleVisibility: .visible) {
            Button("Delete host", role: .destructive) { if let host = deleteHost { store.delete(host) }; deleteHost = nil }
        } message: { Text("The host will also be removed from Android after its next sync.") }
        .onReceive(NotificationCenter.default.publisher(for: .newHarborHost)) { _ in if store.loaded { editor = Host(auth: .none) } }
        .onChange(of: store.loaded) { _, loaded in if !loaded { cancelScan(); editor = nil; candidate = nil; showingSharing = false } }
        .onChange(of: selection) { _, _ in if scanningHost != nil { cancelScan() }; store.activeSession = nil }
        .onChange(of: store.library.hosts.map(\.id)) { before, after in
            if before.isEmpty && after.count == 1 { selection = after.first }
            else if let selection, !after.contains(selection) { self.selection = after.first }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Hosts").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { editor = Host(auth: .none) } label: { Image(systemName: "plus").frame(width: 30, height: 30) }
                    .buttonStyle(.plain).help("New host (⌘N)").accessibilityLabel("New host")
            }.padding(.horizontal, 16).frame(height: 52)
            if store.library.hosts.isEmpty {
                Text("Your hosts will appear here.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 16).padding(.top, 12)
                Spacer()
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                    TextField("Search hosts", text: $query).textFieldStyle(.plain).focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }.font(.system(size: 13)).padding(.horizontal, 10).frame(height: 32)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6)).padding(.horizontal, 12).padding(.bottom, 10)
                if filtered.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No matching hosts").font(.system(size: 14, weight: .semibold))
                        Button("Clear search") { query = ""; searchFocused = true }.font(.system(size: 14))
                    }.padding(20)
                    Spacer()
                } else {
                    List(selection: $selection) {
                        ForEach(groups, id: \.self) { group in
                            Section(group) {
                                ForEach(filtered.filter { ($0.group.isEmpty ? "Ungrouped" : $0.group) == group }) { host in
                                    HStack(spacing: 9) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(host.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                            Text("\(host.username)@\(host.address)").font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1)
                                        }
                                    }.padding(.vertical, 4).tag(host.id)
                                        .listRowBackground(selection == host.id ? Palette.raised : Palette.sidebar)
                                        .contextMenu {
                                            Button("Connect") { connect(host) }
                                            Button("Edit host") { editor = host }
                                            Button("Verify server key") { inspect(host) }
                                            Divider()
                                            Button("Delete host", role: .destructive) { deleteHost = host }
                                        }
                                        .simultaneousGesture(TapGesture().onEnded { selection = host.id; store.activeSession = nil })
                                        .onTapGesture(count: 2) { connect(host) }
                                }
                            }
                        }
                    }.listStyle(.sidebar).scrollContentBackground(.hidden)
                }
            }
            Divider()
            HStack(spacing: 12) {
                Button { showingSharing = true } label: { Label("Devices", systemImage: "iphone").frame(minHeight: 32) }.buttonStyle(.plain)
                Spacer()
                Button { store.lock() } label: { Image(systemName: "lock").frame(width: 32, height: 32) }.buttonStyle(.plain)
                    .help("Lock Harbor").accessibilityLabel("Lock Harbor")
            }.font(.system(size: 13)).padding(.horizontal, 14).padding(.vertical, 8)
        }.background(Palette.sidebar)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(active?.host.name ?? selected?.name ?? "Hosts")
                    .font(.system(size: 19, weight: .semibold)).lineLimit(1)
                Spacer()
                if let active {
                    Button("Host details") { selection = active.host.id; store.activeSession = nil }
                } else if let host = selected {
                    Button("Connect") { connect(host) }.buttonStyle(HarborActionStyle())
                    Menu {
                        Button("Edit host") { editor = host }
                        Button("Verify server key") { inspect(host) }
                        Divider()
                        Button("Delete host", role: .destructive) { deleteHost = host }
                    } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }
                        .menuIndicator(.hidden).menuStyle(.borderlessButton).accessibilityLabel("Host actions")
                }
            }.padding(.horizontal, 24).frame(height: 52)
            Divider()
            if !store.sessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        Button { store.activeSession = nil } label: { Text("Overview").frame(height: 35) }
                            .buttonStyle(.plain).padding(.horizontal, 14)
                            .background(store.activeSession == nil ? Palette.canvas : Palette.sidebar)
                            .overlay(alignment: .bottom) { if store.activeSession == nil { Rectangle().fill(Palette.accent).frame(height: 2) } }
                        ForEach(store.sessions) { session in
                            SessionTab(session: session, active: store.activeSession == session.id,
                                       select: { store.activeSession = session.id }, close: { store.close(session) })
                        }
                    }
                }.background(Palette.sidebar).frame(height: 36)
            }
            if let scanningHost {
                scanWorkspace(scanningHost)
            } else if active != nil {
                ZStack {
                    ForEach(store.sessions) { session in
                        SessionWorkspace(session: session, active: store.activeSession == session.id,
                                         retry: { retry(session) }, edit: { edit(session) }, cancel: { store.close(session) })
                            .opacity(store.activeSession == session.id ? 1 : 0)
                            .allowsHitTesting(store.activeSession == session.id).accessibilityHidden(store.activeSession != session.id)
                    }
                }.padding(8).background(Palette.canvas)
            } else {
                hostOverview
            }
        }
    }

    private var hostOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let host = selected {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connection").font(.system(size: 15, weight: .semibold)).padding(.bottom, 4)
                        detailRow("Hostname", host.address)
                        detailRow("Username", host.username)
                        detailRow("Port", String(host.port))
                        detailRow("Authentication", host.auth.label)
                        if !host.group.isEmpty { detailRow("Group", host.group) }
                    }
                    Divider().padding(.vertical, 22)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Server identity").font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Button("Verify…") { inspect(host) }.font(.system(size: 13))
                        }
                        if let fingerprint = fingerprint(host) {
                            Text("Approved fingerprint").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                            Text(fingerprint).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        } else {
                            Text("Not verified. Connect to review the server fingerprint.")
                                .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        }
                    }
                    if !host.notes.isEmpty {
                        Divider().padding(.vertical, 22)
                        Text("Notes").font(.system(size: 15, weight: .semibold)).padding(.bottom, 10)
                        Text(host.notes).font(.system(size: 13)).textSelection(.enabled)
                    }
                } else if store.library.hosts.isEmpty {
                    Text("No hosts yet").font(.system(size: 19, weight: .semibold)).padding(.bottom, 8)
                    Text("Add an SSH host to get started.").font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.bottom, 18)
                    Button("Add host") { editor = Host(auth: .none) }.buttonStyle(HarborActionStyle())
                } else {
                    Text("Select a host").font(.system(size: 19, weight: .semibold)).padding(.bottom, 8)
                    Text("Choose a host from the sidebar to see its details.")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
            }.frame(maxWidth: 620, alignment: .leading).padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Palette.secondary).frame(width: 118, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 13))
    }

    private func fingerprint(_ host: Host) -> String? {
        guard let line = host.knownHosts.split(whereSeparator: \.isNewline).first(where: { !$0.hasPrefix("#") }),
              let encoded = line.split(separator: " ").dropFirst(2).first,
              let key = Data(base64Encoded: String(encoded)) else { return nil }
        return "SHA256:" + Data(SHA256.hash(data: key)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    private func connect(_ host: Host) {
        if host.knownHosts.isEmpty { inspect(host) }
        else { store.connect(host) }
    }
    private func inspect(_ host: Host) {
        let token = UUID()
        scanToken = token
        scanningHost = host
        scanError = nil
        Task {
            do {
                let value = try await SSH.inspect(host)
                guard scanToken == token, store.loaded else { return }
                scanningHost = nil
                candidate = value
            } catch {
                guard scanToken == token, store.loaded else { return }
                scanError = error.localizedDescription
            }
        }
    }
    private func cancelScan() {
        scanToken = UUID()
        scanningHost = nil
        scanError = nil
    }
    private func retry(_ session: TerminalSession) {
        let id = session.host.id
        store.close(session)
        if let host = store.library.hosts.first(where: { $0.id == id }) { connect(host) }
    }
    private func edit(_ session: TerminalSession) {
        let id = session.host.id
        store.close(session)
        editor = store.library.hosts.first(where: { $0.id == id })
    }
    private func scanWorkspace(_ host: Host) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: scanError == nil ? "checkmark.shield" : "exclamationmark.shield")
                .font(.system(size: 34, weight: .light)).foregroundStyle(Palette.accent)
            Text(scanError == nil ? "Checking server identity" : "Could not check server identity")
                .font(.system(size: 27, weight: .semibold))
            Text("\(host.username)@\(host.address):\(String(host.port))")
                .font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.secondary)
            if let scanError {
                Text(scanError).font(.system(size: 14)).foregroundStyle(Palette.secondary)
            } else {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Retrieving the server key for your approval…")
                        .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                }
            }
            HStack(spacing: 12) {
                if scanError != nil { Button("Retry") { if let latest = store.library.hosts.first(where: { $0.id == host.id }) { inspect(latest) } }.buttonStyle(HarborActionStyle()) }
                Button("Edit Config") { cancelScan(); editor = store.library.hosts.first(where: { $0.id == host.id }) }.buttonStyle(.bordered)
                Button("Cancel") { cancelScan() }.buttonStyle(.bordered)
            }
        }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct SessionTab: View {
    @ObservedObject var session: TerminalSession
    let active: Bool
    let select: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 9) {
            Button(action: select) {
                HStack(spacing: 6) {
                    Circle().fill(session.status == "Session open" ? Palette.accent : Color.secondary).frame(width: 5, height: 5)
                    Text(session.host.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
            }.buttonStyle(.plain)
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).accessibilityLabel("Close \(session.host.name) session")
        }.padding(.horizontal, 12).frame(height: 35).background(active ? Palette.canvas : Palette.sidebar)
            .overlay(alignment: .bottom) { if active { Rectangle().fill(Palette.accent).frame(height: 2) } }.help(session.status)
    }
}

struct SessionWorkspace: View {
    @ObservedObject var session: TerminalSession
    let active: Bool
    let retry: () -> Void
    let edit: () -> Void
    let cancel: () -> Void

    var body: some View {
        Group {
            if session.phase == .ready {
                TerminalSurface(session: session, active: active)
            } else {
                ConnectionProgressView(session: session, retry: retry, edit: edit, cancel: cancel)
            }
        }
    }
}

struct ConnectionProgressView: View {
    @ObservedObject var session: TerminalSession
    let retry: () -> Void
    let edit: () -> Void
    let cancel: () -> Void
    @State private var serverMessage = ""
    private let steps: [ConnectionPhase] = [.connecting, .verifying, .authenticating, .openingShell]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                Text(session.phase == .failed ? "Connection failed" : session.phase == .ended ? "Session ended" : "Connecting")
                    .font(.system(size: 20, weight: .semibold)).padding(.bottom, 8)
                Text("\(session.host.username)@\(session.host.address):\(String(session.host.port))")
                    .font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.secondary)
                    .textSelection(.enabled).padding(.bottom, 28)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps, id: \.rawValue) { step in
                        HStack(spacing: 14) {
                            Group {
                                if session.lastMilestone.rawValue > step.rawValue {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                                } else if session.phase == step {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "circle").foregroundStyle(Palette.secondary)
                                }
                            }.frame(width: 20, height: 20)
                            Text(step.title).foregroundStyle(session.phase == step ? Palette.text : Palette.secondary)
                        }.font(.system(size: 14)).frame(height: 42)
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))
                if let failure = session.failure {
                    Text(failure).font(.system(size: 14)).foregroundStyle(Palette.text)
                        .padding(.top, 20).fixedSize(horizontal: false, vertical: true)
                }
                if !serverMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Server message").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                        Text(serverMessage).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 10)).padding(.top, 18)
                }
                }.frame(maxWidth: 540, alignment: .leading).padding(.horizontal, 44).padding(.top, 36).padding(.bottom, 26)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack(spacing: 12) {
                if session.phase == .failed || session.phase == .ended {
                    Button("Retry") { retry() }.buttonStyle(HarborActionStyle())
                    Button("Edit Config") { edit() }.buttonStyle(.bordered)
                    Button("Close") { cancel() }.buttonStyle(.bordered)
                } else {
                    Button("Cancel") { cancel() }.buttonStyle(.bordered)
                }
                Spacer()
            }.frame(maxWidth: 540, alignment: .leading).padding(.horizontal, 44).padding(.vertical, 17)
                .frame(maxWidth: .infinity, alignment: .leading).background(Palette.sidebar)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()) { _ in
                guard session.phase == .authenticating || session.phase == .openingShell else { return }
                let data = session.terminal.getTerminal().getBufferAsData(kind: .normal)
                let text = String(decoding: data.suffix(2048), as: UTF8.self)
                let safe = String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.value == 10 || $0.value >= 32 }))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                serverMessage = String(safe.suffix(1200))
            }
    }
}
