import MuxyShared
import SwiftUI

struct AgentKindIconView: View {
    let kind: AgentKind
    var size: CGFloat = 13
    var color: Color = MuxyTheme.fgMuted

    var body: some View {
        if let iconName = kind.providerIconName {
            ProviderIconView(iconName: iconName, size: size, style: .monochrome(color))
                .scaleEffect(providerScale)
                .frame(width: size, height: size)
        } else {
            Image(systemName: kind.iconSystemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }

    private var providerScale: CGFloat {
        switch kind {
        case .terminal:
            1
        case .claudeCode,
             .codex:
            1.2
        case .geminiCli:
            1.08
        case .openCode:
            1
        }
    }
}
