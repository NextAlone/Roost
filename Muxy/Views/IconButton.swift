import SwiftUI

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 13
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(hovered ? MuxyTheme.text : MuxyTheme.textMuted)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
