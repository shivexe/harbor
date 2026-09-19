import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct SharingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LibraryStore
    @ObservedObject var sharing: SharingService
    @State private var revoke: PairedDevice?
    @State private var optionsOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Devices").font(.system(size: 28, weight: .semibold))
                    Text("Pair Android to receive this Mac’s host library.")
                        .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
            }.padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    pairingPanel
                    DisclosureGroup(isExpanded: $optionsOpen) {
                        connectionOptions.padding(.top, 16)
                    } label: {
                        Text("Connection options").font(.system(size: 14, weight: .medium))
                    }.tint(Palette.accent)
                    Divider()
                    devicesPanel
                }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(width: 720, height: 650).background(Palette.sidebar)
            .tint(Palette.accent).foregroundStyle(Palette.text)
            .onAppear { sharing.discoverNetworks() }
            .confirmationDialog("Revoke \(revoke?.name ?? "device")?", isPresented: Binding(get: { revoke != nil }, set: { if !$0 { revoke = nil } }), titleVisibility: .visible) {
                Button("Revoke device", role: .destructive) { if let device = revoke { sharing.revoke(device) }; revoke = nil }
            } message: { Text("This blocks future sync. Rotate server credentials to remove SSH access already stored on the phone.") }
    }

    @ViewBuilder
    private var pairingPanel: some View {
        if sharing.preparing {
            VStack(alignment: .leading, spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Preparing a pairing code…").font(.system(size: 18, weight: .semibold))
            }.frame(maxWidth: .infinity, minHeight: 300, alignment: .leading)
        } else if let result = sharing.pairingResult, sharing.approvedPairing {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(.green)
                Text("Android paired").font(.system(size: 22, weight: .semibold))
                Text(result).font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Button("Pair another device") { sharing.inviteAutomatically() }.buttonStyle(HarborActionStyle())
            }.frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
        } else if let pending = sharing.pending, sharing.pairingResult == nil {
            VStack(alignment: .leading, spacing: 18) {
                Text("Compare the codes").font(.system(size: 22, weight: .semibold))
                Text("\(pending.name) wants to pair. Confirm the same code appears on Android.")
                    .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Text(pending.code).font(.system(size: 48, weight: .medium, design: .monospaced))
                    .tracking(4).foregroundStyle(Palette.accent)
                    .accessibilityLabel("Comparison code \(pending.code.map(String.init).joined(separator: " "))")
                HStack(spacing: 12) {
                    Button("Deny") { sharing.deny() }.controlSize(.large)
                    Button("Codes match — approve") { sharing.approve() }.buttonStyle(HarborActionStyle())
                }
            }.frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
        } else if sharing.pairingResult != nil {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pairing request denied").font(.system(size: 22, weight: .semibold))
                Text("Generate a new code to try again.").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Button("Generate new code") { sharing.inviteAutomatically() }.buttonStyle(HarborActionStyle())
            }.frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
        } else if let invitation = sharing.invitation {
            VStack(alignment: .leading, spacing: 20) {
                Text("Scan with Harbor on Android").font(.system(size: 22, weight: .semibold))
                HStack(alignment: .top, spacing: 24) {
                    if let image = qr(sharing.invitationText) {
                        Image(nsImage: image).interpolation(.none).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 288, height: 288).padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Pairing QR code. Contains a one-time secret.")
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Open Harbor on your phone and scan this code.")
                            .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                        Text("Both devices must be on the same local network or private VPN.")
                            .font(.system(size: 14)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("Expires \(Date(timeIntervalSince1970: TimeInterval(invitation.expiresAt)), style: .relative)")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        Button("Cancel code") { sharing.cancelInvitation() }.controlSize(.large)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else if sharing.invitationExpired {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "clock.badge.exclamationmark").font(.system(size: 32)).foregroundStyle(Palette.accent)
                Text("Pairing code expired").font(.system(size: 22, weight: .semibold))
                Text("Generate a new one to continue pairing.").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Button("Generate new code") { sharing.inviteAutomatically() }.buttonStyle(HarborActionStyle())
            }.frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
        } else if let error = sharing.error {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 32)).foregroundStyle(Palette.accent)
                Text("Pairing could not start").font(.system(size: 22, weight: .semibold))
                Text(error).font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Button("Retry") { sharing.inviteAutomatically() }.buttonStyle(HarborActionStyle())
            }.frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "qrcode").font(.system(size: 36)).foregroundStyle(Palette.accent)
                Text("Pair your Android device").font(.system(size: 22, weight: .semibold))
                Text("Scan a one-time code with Harbor on Android. You’ll compare a short code before approving.")
                    .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                    .frame(maxWidth: 430, alignment: .leading)
                Button("Pair Android") { sharing.inviteAutomatically() }.buttonStyle(HarborActionStyle())
            }.frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
        }
        if let error = sharing.error, sharing.invitation != nil {
            Text(error).font(.system(size: 12)).foregroundStyle(.red)
        }
    }

    private var connectionOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            if sharing.networks.isEmpty {
                Text("No local network available. Connect to Wi-Fi, Ethernet or a private VPN.")
                    .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Button("Check again") { sharing.discoverNetworks() }.controlSize(.large)
            } else {
                Text("Network for pairing").font(.system(size: 14, weight: .medium))
                Picker("Network for pairing", selection: Binding(get: { sharing.address }, set: { sharing.selectNetwork($0) })) {
                    if sharing.address.isEmpty { Text("Choose a network").tag("") }
                    ForEach(sharing.networks) { network in
                        Text("\(network.name) · \(network.address)").tag(network.address)
                    }
                }.labelsHidden().frame(maxWidth: 420, alignment: .leading)
                    .disabled(sharing.pending != nil)
                Text("Choose the network your phone can reach. Changing it generates a new code.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            if sharing.invitation != nil {
                Button("Copy pairing details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(sharing.invitationText, forType: .string)
                }.controlSize(.large)
            }
            if !store.library.devices.isEmpty {
                Toggle("Allow paired devices to sync", isOn: Binding(
                    get: { sharing.enabled },
                    set: { if $0 { sharing.enableSync() } else { sharing.stop() } }
                )).toggleStyle(.switch).font(.system(size: 14))
            }
            Text(sharing.enabled ? "Sync is available while Harbor is unlocked and open." : "Sync is currently stopped.")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
    }

    private var devicesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paired devices").font(.system(size: 18, weight: .semibold))
            if store.library.devices.isEmpty {
                Text("No devices paired yet.").font(.system(size: 14)).foregroundStyle(Palette.secondary)
            } else {
                ForEach(store.library.devices) { device in
                    HStack(spacing: 14) {
                        Image(systemName: "iphone").font(.system(size: 19)).foregroundStyle(Palette.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name).font(.system(size: 14, weight: .medium))
                            Text("Paired \(Date(timeIntervalSince1970: TimeInterval(device.pairedAt)), format: .dateTime.day().month().year())")
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Button("Revoke") { revoke = device }.controlSize(.large)
                    }.padding(.vertical, 8)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func qr(_ value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let bitmap = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: bitmap, size: NSSize(width: image.extent.width, height: image.extent.height))
    }
}
