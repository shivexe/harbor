import AppKit
import SwiftUI

@main
struct HarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: LibraryStore
    @StateObject private var sharing: SharingService

    init() {
        let store = LibraryStore()
        let sharing = SharingService(store: store)
        store.onLock = { [weak sharing] in sharing?.stop() }
        _store = StateObject(wrappedValue: store)
        _sharing = StateObject(wrappedValue: sharing)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, sharing: sharing)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { delegate.store = store }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New host") { NotificationCenter.default.post(name: .newHarborHost, object: nil) }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .appSettings) {
                Button("Lock vault") { store.lock() }.keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: LibraryStore?
    private var screenObserver: NSObjectProtocol?
    private var eventMonitor: Any?
    private var idleTimer: Timer?
    private var lastActivity = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        screenObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.store?.lock() } }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .leftMouseDown, .rightMouseDown]) { [weak self] event in self?.lastActivity = Date(); return event }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, Date().timeIntervalSince(self.lastActivity) >= 900 else { return }
                self.store?.lock()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.lock()
        idleTimer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let screenObserver { DistributedNotificationCenter.default().removeObserver(screenObserver) }
    }
}

extension Notification.Name {
    static let newHarborHost = Notification.Name("app.harbor.new-host")
}
