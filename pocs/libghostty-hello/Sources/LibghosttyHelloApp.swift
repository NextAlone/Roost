import SwiftUI

@main
struct LibghosttyHelloApp: App {
    var body: some Scene {
        WindowGroup("Libghostty Hello") {
            ContentView()
                .frame(minWidth: 640, minHeight: 400)
                .frame(idealWidth: 960, idealHeight: 600)
        }
        .windowResizability(.contentSize)
    }
}
