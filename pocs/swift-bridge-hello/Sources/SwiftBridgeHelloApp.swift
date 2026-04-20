import SwiftUI

@main
struct SwiftBridgeHelloApp: App {
    var body: some Scene {
        WindowGroup("swift-bridge × Rust") {
            ContentView()
                .frame(minWidth: 420, minHeight: 260)
        }
        .windowResizability(.contentSize)
    }
}
