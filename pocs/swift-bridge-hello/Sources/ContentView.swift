import SwiftUI

struct ContentView: View {
    @State private var name: String = ""
    @State private var greeting: String = "(click Greet to call Rust)"
    private let bridgeVersion: String = roost_bridge_version().toString()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "link.circle.fill")
                    .foregroundStyle(.orange)
                Text("swift-bridge × Rust")
                    .font(.title2).bold()
                Spacer()
                Text("roost-bridge \(bridgeVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Name").font(.subheadline).foregroundStyle(.secondary)
                TextField("World", text: $name, onCommit: callRust)
                    .textFieldStyle(.roundedBorder)

                Button("Greet", action: callRust)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

            Divider()

            Text(greeting)
                .font(.body.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
    }

    private func callRust() {
        greeting = roost_greet(name).toString()
    }
}

#Preview {
    ContentView()
}
