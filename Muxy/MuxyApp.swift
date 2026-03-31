import SwiftUI
import AppKit

@main
struct MuxyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var projectStore = ProjectStore()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(appState)
                .environment(projectStore)
                .preferredColorScheme(.dark)
                .background(WindowConfigurator())
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .defaultSize(width: 1200, height: 800)
        .commands {
            MuxyCommands(appState: appState)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        _ = GhosttyService.shared
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
            w.backgroundColor = MuxyTheme.nsBg
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
