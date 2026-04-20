import SwiftUI

@main
struct RoostApp: App {
    var body: some Scene {
        WindowGroup("Roost") {
            RootView()
                .frame(minWidth: 640, minHeight: 400)
                .frame(idealWidth: 960, idealHeight: 600)
        }
        .windowResizability(.contentSize)
    }
}
