import AppKit
import SwiftUI

struct Palette {
    static let canvas = Color(red: 23.0 / 255, green: 25.0 / 255, blue: 31.0 / 255)
    static let sidebar = Color(red: 29.0 / 255, green: 32.0 / 255, blue: 40.0 / 255)
    static let raised = Color(red: 39.0 / 255, green: 43.0 / 255, blue: 53.0 / 255)
    static let accent = Color(red: 168.0 / 255, green: 184.0 / 255, blue: 250.0 / 255)
    static let text = Color(red: 241.0 / 255, green: 242.0 / 255, blue: 246.0 / 255)
    static let secondary = Color(red: 171.0 / 255, green: 177.0 / 255, blue: 192.0 / 255)
}

struct HarborActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.canvas)
            .padding(.horizontal, 18).frame(minHeight: 38)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 8))
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

    var body: some View {
        Group {
            if store.loaded {
                HSplitView {
                    sidebar.frame(minWidth: 250, idealWidth: 272, maxWidth: 330)
                    workspace.frame(minWidth: 610, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "lock.shield").font(.system(size: 36)).foregroundStyle(Palette.accent)
                    Text("Harbor is locked").font(.system(size: 28, weight: .semibold))
                    Text("Unlock to use your hosts and sync with Android.").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                    Button(store.authenticating ? "Unlocking…" : "Unlock Harbor") { Task { await store.unlock() } }
                        .buttonStyle(HarborActionStyle()).disabled(store.authenticating)
                }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .background(Palette.canvas)
        .tint(Palette.accent)
        .foregroundStyle(Palette.text)
        .sheet(item: $editor) { host in HostEditor(host: host, store: store) { saved in query = ""; selection = saved.id } }
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
        .onChange(of: selection) { _, _ in if scanningHost != nil { cancelScan() } }
        .onChange(of: store.library.hosts.map(\.id)) { before, after in
            if before.isEmpty && after.count == 1 { selection = after.first }
            else if let selection, !after.contains(selection) { self.selection = after.first }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill").foregroundStyle(Palette.accent).font(.system(size: 19))
                Text("Harbor").font(.system(size: 20, weight: .semibold))
                Spacer()
                if !store.library.hosts.isEmpty {
                    Button { editor = Host(auth: .none) } label: { Image(systemName: "plus").frame(width: 36, height: 36) }
                        .buttonStyle(.plain).help("New host (⌘N)").accessibilityLabel("New host")
                }
            }.padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 24)
            if store.library.hosts.isEmpty {
                Text("Your hosts will appear here.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 20).padding(.top, 8)
                Spacer()
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                    TextField("Search hosts", text: $query).textFieldStyle(.plain).focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }.font(.system(size: 14)).padding(.horizontal, 12).frame(height: 38)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 16).padding(.bottom, 16)
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
                                    HStack(spacing: 12) {
                                        Image(systemName: "server.rack").foregroundStyle(Palette.accent).frame(width: 18)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(host.name).font(.system(size: 14, weight: .medium))
                                            Text("\(host.username)@\(host.address)").font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1)
                                        }
                                    }.padding(.vertical, 7).tag(host.id)
                                        .listRowBackground(selection == host.id ? Palette.raised : Palette.sidebar)
                                        .contextMenu {
                                            Button("Connect") { connect(host) }
                                            Button("Edit host") { editor = host }
                                            Button("Verify server key") { inspect(host) }
                                            Divider()
                                            Button("Delete host", role: .destructive) { deleteHost = host }
                                        }
                                        .onTapGesture(count: 2) { connect(host) }
                                }
                            }
                        }
                    }.listStyle(.sidebar).scrollContentBackground(.hidden)
                }
            }
            Divider()
            HStack(spacing: 12) {
                Button { showingSharing = true } label: { Label("Devices", systemImage: "iphone").frame(minHeight: 36) }.buttonStyle(.plain)
                Spacer()
                Button { store.lock() } label: { Image(systemName: "lock").frame(width: 36, height: 36) }.buttonStyle(.plain)
                    .help("Lock Harbor").accessibilityLabel("Lock Harbor")
            }.font(.system(size: 14)).padding(.horizontal, 18).padding(.vertical, 10)
        }.background(Palette.sidebar)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(store.sessions.isEmpty ? "Hosts" : "Sessions").font(.system(size: 28, weight: .semibold))
                Spacer()
                if !store.library.hosts.isEmpty {
                    Button { editor = Host(auth: .none) } label: { Label("Add host", systemImage: "plus") }
                        .buttonStyle(.bordered).controlSize(.large)
                }
            }.padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 22)
            Divider()
            if let scanningHost {
                scanWorkspace(scanningHost)
            } else if store.sessions.isEmpty {
                emptyWorkspace
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(store.sessions) { session in
                            SessionTab(session: session, active: store.activeSession == session.id, select: { store.activeSession = session.id }, close: { store.close(session) })
                        }
                    }
                }.background(Palette.sidebar).frame(height: 44)
                ZStack {
                    ForEach(store.sessions) { session in
                        SessionWorkspace(session: session, active: store.activeSession == session.id,
                                         retry: { retry(session) }, edit: { edit(session) }, cancel: { store.close(session) })
                            .opacity(store.activeSession == session.id ? 1 : 0)
                            .allowsHitTesting(store.activeSession == session.id).accessibilityHidden(store.activeSession != session.id)
                    }
                }.padding(12).background(Palette.canvas)
            }
        }
    }

    private var emptyWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: selected == nil ? "server.rack" : "terminal").font(.system(size: 36, weight: .light)).foregroundStyle(Palette.accent)
                if let host = selected {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(host.name).font(.system(size: 28, weight: .semibold))
                        Text("\(host.username)@\(host.address):\(String(host.port))").font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Palette.secondary).textSelection(.enabled)
                    }
                    HStack(spacing: 12) {
                        Button { connect(host) } label: { Label("Connect", systemImage: "terminal") }
                            .buttonStyle(HarborActionStyle())
                        Button("Edit host") { editor = host }.buttonStyle(.bordered).controlSize(.large)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        detailRow("Authentication", host.auth.label)
                        detailRow("Server identity", host.knownHosts.isEmpty ? "Verify before connecting" : "Trusted server key")
                        if !host.group.isEmpty { detailRow("Group", host.group) }
                        if !host.notes.isEmpty { detailRow("Notes", host.notes) }
                    }.padding(.top, 8)
                } else if store.library.hosts.isEmpty {
                    Text("Add your first host").font(.system(size: 28, weight: .semibold))
                    Text("Enter a server address and username, then choose how to authenticate. You can connect as soon as it is saved.")
                        .font(.system(size: 14)).foregroundStyle(Palette.secondary).frame(maxWidth: 440, alignment: .leading)
                    Button("Add host") { editor = Host(auth: .none) }.buttonStyle(HarborActionStyle())
                } else {
                    Text("Choose a host").font(.system(size: 28, weight: .semibold))
                    Text("Select a host in the sidebar to see its connection details.")
                        .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                }
            }.padding(48).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(label).foregroundStyle(Palette.secondary).frame(width: 130, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: 450, alignment: .leading)
        }.font(.system(size: 14))
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
        HStack(spacing: 12) {
            Button(action: select) {
                HStack(spacing: 8) {
                    Circle().fill(session.status == "Session open" ? Palette.accent : Color.secondary).frame(width: 6, height: 6)
                    Text(session.host.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
            }.buttonStyle(.plain)
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).accessibilityLabel("Close \(session.host.name) session")
        }.padding(.horizontal, 16).frame(height: 43).background(active ? Palette.canvas : Palette.sidebar)
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
        ZStack {
            TerminalSurface(session: session, active: active && session.lastMilestone == .ready)
                .opacity(session.lastMilestone == .ready ? 1 : 0)
                .allowsHitTesting(session.lastMilestone == .ready)
                .accessibilityHidden(session.lastMilestone != .ready)
            if session.lastMilestone != .ready {
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
                Image(systemName: session.phase == .failed ? "exclamationmark.circle" : "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 35, weight: .light)).foregroundStyle(Palette.accent)
                    .padding(.bottom, 20)
                Text(session.phase == .failed ? "Connection failed" : session.phase == .ended ? "Session ended" : "Connecting to \(session.host.name)")
                    .font(.system(size: 28, weight: .semibold)).padding(.bottom, 8)
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
