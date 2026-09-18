import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct SharingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LibraryStore
    @ObservedObject var sharing: SharingService
    @State private var revoke: PairedDevice?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your devices").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("This Mac manages your library. Android receives it when you sync.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Toggle("Allow local sync", isOn: Binding(get: { sharing.enabled }, set: { if $0 { sharing.start() } else { sharing.stop() } })).toggleStyle(.switch)
                Spacer()
                Circle().fill(sharing.enabled ? Palette.accent : Color.secondary).frame(width: 6, height: 6)
                Text(sharing.enabled ? "Sharing enabled" : "Sharing stopped").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack {
                TextField("Local IP address", text: $sharing.address).textFieldStyle(.roundedBorder).disabled(sharing.enabled)
                TextField("Port", text: $sharing.port).frame(width: 90).textFieldStyle(.roundedBorder).disabled(sharing.enabled)
                Button("Pair device") { sharing.invite() }.buttonStyle(.borderedProminent)
            }.disabled(sharing.invitation != nil && !sharing.approvedPairing)
            Text("Use this Mac’s local IP address. Both devices must be reachable on the same network or private VPN.").font(.system(size: 12)).foregroundStyle(.secondary)
            if let invitation = sharing.invitation {
                HStack(alignment: .top, spacing: 22) {
                    if let qr = qr(sharing.invitationText) {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 190, height: 190).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10)).accessibilityLabel("Pairing QR code. Contains a one-time secret.")
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Scan with Harbor on Android").font(.system(size: 17, weight: .semibold))
                        Text("Expires \(Date(timeIntervalSince1970: TimeInterval(invitation.expiresAt)), style: .relative). Compare the code on both devices before approving.").font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Copy pairing JSON") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(sharing.invitationText, forType: .string)
                        }
                        if !sharing.approvedPairing { Button("Cancel invitation") { sharing.cancelInvitation() } }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 12))
            }
            if let result = sharing.pairingResult { Text(result).font(.system(size: 13)).foregroundStyle(Palette.accent) }
            if let pending = sharing.pending, sharing.pairingResult == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(pending.name) wants to pair").font(.system(size: 16, weight: .medium))
                    Text(pending.code).font(.system(size: 35, weight: .medium, design: .monospaced)).foregroundStyle(Palette.accent).accessibilityLabel("Comparison code \(pending.code.map(String.init).joined(separator: " "))")
                    Text("Only approve if the Android device shows this exact code.").font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Button("Deny") { sharing.deny() }
                        Button("Codes match — approve") { sharing.approve() }.buttonStyle(.borderedProminent)
                    }
                }
            }
            Divider()
            Text("Paired devices").font(.system(size: 15, weight: .semibold))
            if store.library.devices.isEmpty {
                Text("No devices paired yet.").font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                ForEach(store.library.devices) { device in
                    HStack(spacing: 12) {
                        Image(systemName: "iphone").font(.system(size: 22)).foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name)
                            Text("Paired \(Date(timeIntervalSince1970: TimeInterval(device.pairedAt)), format: .dateTime.day().month().year())").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Revoke") { revoke = device }
                    }
                }
            }
            if let error = sharing.error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
        }.padding(28).frame(width: 720).background(Palette.sidebar).tint(Palette.accent)
        .confirmationDialog("Revoke \(revoke?.name ?? "device")?", isPresented: Binding(get: { revoke != nil }, set: { if !$0 { revoke = nil } }), titleVisibility: .visible) {
            Button("Revoke device", role: .destructive) { if let device = revoke { sharing.revoke(device) }; revoke = nil }
        } message: { Text("This blocks future sync. Rotate server credentials to remove SSH access already stored on the phone.") }
    }

    private func qr(_ value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 5, y: 5)),
              let bitmap = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: bitmap, size: NSSize(width: image.extent.width, height: image.extent.height))
    }
}
