import SwiftUI
import CoreImage.CIFilterBuiltins
import CursorDesign

@main
struct TheCursorApp: App {
    @NSApplicationDelegateAdaptor(CursorAppDelegate.self) private var appDelegate
    @StateObject private var bluetooth = BluetoothController()
    @StateObject private var screen = ScreenViewer()
    var body: some Scene {
        Window("The Cursor", id: "main") {
            ContentView(bluetooth: bluetooth, screen: screen)
                .preferredColorScheme(.dark)
                .onDisappear { screen.setEnabled(false); bluetooth.stop() }
        }
        .defaultSize(width: 800, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Control") {
                Button("Release Cursor") { bluetooth.releaseCapture?() }.keyboardShortcut(.escape, modifiers: [])
                Button("End Session") { bluetooth.stop() }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var bluetooth: BluetoothController
    @ObservedObject var screen: ScreenViewer
    @State private var showPairingCode = false
    @State private var showHelp = false
    private var needsCode: Bool {
        bluetooth.started && (!bluetooth.ready || showPairingCode || !bluetooth.companionConnected)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 10) {
                        CursorLogo(size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("The Cursor").font(.system(size: 19, weight: .semibold))
                            Text("A little closer.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        Circle().fill(bluetooth.ready ? CursorPalette.aqua : .white.opacity(0.45))
                            .frame(width: 6, height: 6)
                        Text(bluetooth.captured ? "In control" : bluetooth.ready ? "Connected" : bluetooth.started ? "Pairing" : "Ready")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button { showHelp.toggle() } label: {
                            Image(systemName: "questionmark.circle")
                        }.buttonStyle(.plain).accessibilityLabel("Connection help")
                            .popover(isPresented: $showHelp) { helpContent.padding(24).frame(width: 310) }
                    }.help(bluetooth.status)
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text(screen.enabled ? "Live view" : "Control pad")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        Picker("View source", selection: Binding(get: { screen.source }, set: {
                            bluetooth.releaseCapture?(); screen.setSource($0)
                        })) {
                            ForEach(ScreenViewer.Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).accessibilityLabel("View source")
                        Toggle("Screen view", isOn: Binding(get: { screen.enabled }, set: {
                            bluetooth.releaseCapture?(); screen.setEnabled($0)
                        })).toggleStyle(.switch).controlSize(.small)
                    }
                    Divider()
            VStack(spacing: 12) {
                if screen.enabled {
                    Text(screen.status).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if let problem = bluetooth.problem {
                    Text(problem).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center).textSelection(.enabled)
                }
                if bluetooth.ready && !bluetooth.keyboardReady {
                    Text("Keyboard not ready? Re-pair this Mac in iPhone Bluetooth settings.")
                        .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
                HStack(spacing: 8) {
                    Text("esc").font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                    Text("to let go").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    if bluetooth.started || bluetooth.preview {
                        if bluetooth.started {
                            Button(showPairingCode ? "Hide code" : "Pair iPhone") {
                                bluetooth.releaseCapture?(); showPairingCode.toggle()
                            }.buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        Button("End session") { bluetooth.stop() }
                            .buttonStyle(.bordered).controlSize(.large)
                    } else {
                        Button("Connect iPhone") { bluetooth.start() }
                            .buttonStyle(.borderedProminent).tint(CursorPalette.aqua)
                            .foregroundStyle(CursorPalette.ink).controlSize(.large)
                        Button("Preview") { bluetooth.beginPreview() }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                Text(bluetooth.ready ? (bluetooth.keyboardReady ? "Mouse + keyboard · Private by design" : "Mouse connected") : "No accounts. Just your devices.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
                    CreatorCredit()
                }.padding(8)
            }
            .scrollIndicators(.hidden)
            .frame(width: 240)
            GeometryReader { geometry in
                let ratio = screen.enabled ? (screen.frameSize.map { $0.width / $0.height } ?? bluetooth.screenWidth / bluetooth.screenHeight) : bluetooth.screenWidth / bluetooth.screenHeight
                let width = max(1, min(geometry.size.width, geometry.size.height * ratio))
                ZStack {
                    RoundedRectangle(cornerRadius: 30).fill(.ultraThinMaterial)
                    if screen.enabled && screen.hasFrames {
                        if screen.source == .wireless, let image = screen.wirelessImage {
                            Image(nsImage: image).resizable().scaledToFit().allowsHitTesting(false)
                        } else {
                            PhoneScreenPreview(session: screen.session).allowsHitTesting(false)
                        }
                    }
                    CapturePad(bluetooth: bluetooth, showsScreen: screen.enabled && screen.hasFrames)
                    if screen.enabled && !screen.hasFrames && !needsCode {
                        VStack(spacing: 14) {
                            Image(systemName: "iphone.and.arrow.forward").font(.system(size: 26)).foregroundStyle(CursorPalette.aqua)
                            Text(screen.status).font(.system(size: 12)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).padding(.horizontal, 22)
                        }.allowsHitTesting(false)
                    }
                    if !bluetooth.captured && (needsCode || !screen.enabled) {
                        VStack(spacing: 17) {
                            if needsCode {
                                    if let image = qr(bluetooth.pairing.url.absoluteString) {
                                    Image(nsImage: image).interpolation(.none).resizable()
                                        .frame(width: min(width - 48, 176), height: min(width - 48, 176))
                                        .padding(11).background(.white, in: RoundedRectangle(cornerRadius: 18))
                                }
                                Text("Meet your Mac.").font(.system(size: 16, weight: .medium))
                                Text("Scan with your iPhone camera.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            } else {
                                CursorMark().fill(CursorPalette.aqua.opacity(0.9)).frame(width: 42, height: 42)
                                Text(bluetooth.ready || bluetooth.preview ? "Click to take control" : "Your iPhone, within reach.")
                                    .font(.system(size: 14, weight: .medium))
                                Text(bluetooth.preview ? "Local preview" : bluetooth.ready ? "Move. Swipe. Type." : "Connect when you’re ready.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        .multilineTextAlignment(.center).padding(12).allowsHitTesting(false)
                    }
                }
                .frame(width: max(1, width), height: max(1, width / ratio))
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(
                    LinearGradient(colors: [.white.opacity(bluetooth.captured ? 0.5 : 0.25), .white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 30, x: 0, y: 15)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 600)
        .background(WaterBackdrop())
        .background(WindowGlass())
        .onAppear { screen.configure(token: bluetooth.pairing.token); bluetooth.resumeRememberedPairing() }
        .onChange(of: bluetooth.pairing.token) { _, token in screen.configure(token: token) }
        .onChange(of: bluetooth.companionConnected) { _, linked in if linked { showPairingCode = false } }
        .onChange(of: bluetooth.started) { _, started in if !started { showPairingCode = false } }
    }
    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Make the connection.").font(.title3.weight(.semibold))
            Text("1. Scan the code with The Cursor Connect.\n2. Pair this Mac in iPhone Bluetooth settings.\n3. Enable AssistiveTouch in Accessibility → Touch.")
                .font(.callout).foregroundStyle(.secondary).lineSpacing(5)
            Divider()
            Text("Click the pad to capture. Hold and drag to swipe. Select an iPhone text field to type. Esc releases control.")
                .font(.callout).foregroundStyle(.secondary)
            Text(bluetooth.status).font(.caption).foregroundStyle(CursorPalette.aqua).textSelection(.enabled)
            if bluetooth.hasRememberedPairing {
                Text("This iPhone is remembered. Reopening the app reconnects automatically. End session pauses control; Forget pairing requires a new scan.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Forget pairing", role: .destructive) {
                    screen.setEnabled(false); bluetooth.forgetPairing()
                }
            }
            Divider()
            Text("Screen view is optional. For Wi-Fi, use the same network, then tap Share screen in The Cursor Connect (iOS 27+) and approve screen sharing. Video is encrypted and never saved. USB remains available with a trusted data cable. Camera permission is requested only for USB viewing.")
                .font(.caption).foregroundStyle(.secondary)
            if screen.phones.count > 1 {
                Picker("View iPhone", selection: Binding(get: { screen.selectedID }, set: { screen.select($0) })) {
                    Text("Choose iPhone").tag(String?.none)
                    ForEach(screen.phones) { phone in Text(phone.name).tag(Optional(phone.id)) }
                }
            }
        }
    }
    private func qr(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8)
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}

private final class CursorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Update the running Dock tile even if Launch Services cached the old icon.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }
}

private struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = GlassEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
private final class GlassEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.titlebarAppearsTransparent = true
    }
}
