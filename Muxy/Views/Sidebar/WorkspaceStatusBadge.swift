import MuxyShared
import SwiftUI

struct WorkspaceStatusBadge: View {
    let status: WorkspaceStatus

    var body: some View {
        switch status {
        case .clean,
             .unknown:
            EmptyView()
        case .dirty:
            Circle()
                .fill(MuxyTheme.diffHunkFg)
                .frame(width: 6, height: 6)
                .accessibilityLabel("Dirty")
        case .conflicted:
            Circle()
                .fill(MuxyTheme.diffRemoveFg)
                .frame(width: 6, height: 6)
                .accessibilityLabel("Conflicted")
        }
    }
}

extension WorkspaceStatus {
    var sidebarRowBadgeStatus: WorkspaceStatus? {
        switch self {
        case .conflicted:
            self
        case .clean,
             .dirty,
             .unknown:
            nil
        }
    }
}
