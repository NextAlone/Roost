import SwiftUI

struct WelcomeView: View {
    var body: some View {
        Text("No project selected")
            .font(.system(size: 13))
            .foregroundStyle(MuxyTheme.textDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
