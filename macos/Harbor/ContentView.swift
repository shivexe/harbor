import AppKit
import SwiftUI

struct Palette {
    static let canvas = Color(red: 0.035, green: 0.055, blue: 0.087)
    static let sidebar = Color(red: 0.06, green: 0.085, blue: 0.13)
    static let raised = Color(red: 0.085, green: 0.12, blue: 0.18)
    static let accent = Color(red: 0.38, green: 0.65, blue: 0.93)
    static let text = Color(red: 0.86, green: 0.90, blue: 0.95)
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
    @State private var scanning = false

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
                    sidebar.frame(minWidth: 245, idealWidth: 270, maxWidth: 330)
                    workspace.frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield").font(.system(size: 44)).foregroundStyle(Palette.accent)
                    Text("Your vault is locked").font(.system(size: 26, weight: .semibold))
                    Text("Unlock to access your hosts and paired devices.").foregroundStyle(.secondary)
                    Button(store.authenticating ? "Unlocking…" : "Unlock vault") { Task { await store.unlock() } }.buttonStyle(.borderedProminent).disabled(store.authenticating)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.canvas)
        .tint(Palette.accent)
        .foregroundStyle(Palette.text)
        .sheet(item: $editor) { host in HostEditor(host: host, store: store) }
        .sheet(item: $candidate) { value in HostTrustView(candidate: value, store: store) }
        .sheet(isPresented: $showingSharing, onDismiss: { sharing.dismissInvitation() }) { SharingView(store: store, sharing: sharing) }
        .alert("Harbor", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("Delete \(deleteHost?.name ?? "host")?", isPresented: Binding(get: { deleteHost != nil }, set: { if !$0 { deleteHost = nil } }), titleVisibility: .visible) {
            Button("Delete host", role: .destructive) { if let host = deleteHost { store.delete(host) }; deleteHost = nil }
        } message: { Text("The host will also be removed from Android after its next sync.") }
        .onReceive(NotificationCenter.default.publisher(for: .newHarborHost)) { _ in if store.loaded { editor = Host() } }
        .onChange(of: store.loaded) { _, loaded in if !loaded { editor = nil; candidate = nil; showingSharing = false } }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill").foregroundStyle(Palette.accent).font(.system(size: 23))
                Text("Harbor").font(.system(size: 23, weight: .semibold, design: .rounded))
                Spacer()
                Button { editor = Host() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("New host (⌘N)").accessibilityLabel("New host")
            }.padding(.horizontal, 20).padding(.top, 40).padding(.bottom, 24)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search hosts", text: $query).textFieldStyle(.plain)
            }.padding(10).background(Palette.raised, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 16).padding(.bottom, 12)
            List(selection: $selection) {
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(filtered.filter { ($0.group.isEmpty ? "Ungrouped" : $0.group) == group }) { host in
                            HStack(spacing: 10) {
                                Image(systemName: "server.rack").foregroundStyle(Palette.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(host.name).font(.system(size: 13, weight: .medium))
                                    Text("\(host.username)@\(host.address)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }.padding(.vertical, 5).tag(host.id)
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
            if filtered.isEmpty {
                Text(query.isEmpty ? "Add a host to get started." : "No hosts match your search.").font(.system(size: 12)).foregroundStyle(.secondary).padding(20)
            }
            Divider()
            HStack {
                Button { showingSharing = true } label: { Label("Devices", systemImage: "iphone") }.buttonStyle(.plain)
                Spacer()
                Button { store.lock() } label: { Image(systemName: "lock") }.buttonStyle(.plain).help("Lock vault").accessibilityLabel("Lock vault")
            }.font(.system(size: 12)).padding(18)
        }.background(Palette.sidebar)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected?.name ?? "Connections").font(.system(size: 17, weight: .semibold))
                    Text(selected.map { "\($0.username)@\($0.address):\($0.port)" } ?? "Your servers, within reach.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if let host = selected {
                    Button("Edit host") { editor = host }.buttonStyle(.bordered)
                    Button { connect(host) } label: { Label(scanning ? "Verifying…" : "Connect", systemImage: "terminal") }
                        .buttonStyle(.borderedProminent).disabled(scanning)
                }
            }.padding(.horizontal, 24).padding(.top, 40).padding(.bottom, 22)
            Divider()
            if store.sessions.isEmpty {
                emptyWorkspace
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(store.sessions) { session in
                            SessionTab(session: session, active: store.activeSession == session.id, select: { store.activeSession = session.id }, close: { store.close(session) })
                        }
                    }
                }.background(Palette.sidebar).frame(height: 43)
                ZStack {
                    ForEach(store.sessions) { session in
                        TerminalSurface(session: session, active: store.activeSession == session.id).opacity(store.activeSession == session.id ? 1 : 0)
                            .allowsHitTesting(store.activeSession == session.id).accessibilityHidden(store.activeSession != session.id)
                    }
                }.padding(12).background(Palette.canvas)
            }
        }
    }

    private var emptyWorkspace: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "terminal").font(.system(size: 54, weight: .light)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 12) {
                Text(selected == nil ? "A home for your servers." : "Ready when you are.").font(.system(size: 34, weight: .medium, design: .rounded))
                Text(selected == nil ? "Keep your SSH hosts together, open a terminal,\nand bring your library to Android." : "Open a secure SSH session to \(selected!.name).\nYour server’s identity is verified before authentication.")
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            }
            if let host = selected {
                HStack(spacing: 14) {
                    Label(host.auth.label, systemImage: "key")
                    Label(host.knownHosts.isEmpty ? "Key verification required" : "Server key trusted", systemImage: host.knownHosts.isEmpty ? "shield" : "checkmark.shield")
                }.font(.system(size: 12)).foregroundStyle(.secondary)
                if !host.notes.isEmpty { Text(host.notes).font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: 440, alignment: .leading) }
                Button("Connect to \(host.name)") { connect(host) }.buttonStyle(.borderedProminent).disabled(scanning)
            } else {
                Button("Add your first host") { editor = Host() }.buttonStyle(.borderedProminent)
            }
        }.padding(60).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func connect(_ host: Host) {
        if host.knownHosts.isEmpty { inspect(host) }
        else { store.connect(host) }
    }
    private func inspect(_ host: Host) {
        scanning = true
        Task {
            defer { scanning = false }
            do { let value = try await SSH.inspect(host); if store.loaded { candidate = value } }
            catch { store.error = error.localizedDescription }
        }
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
