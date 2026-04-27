import Foundation
import MuxyShared
import SwiftUI

struct VcsWorktreeControllerResolver: Sendable {
    private let resolve: @Sendable (VcsKind) -> any VcsWorktreeController

    init(_ resolve: @escaping @Sendable (VcsKind) -> any VcsWorktreeController) {
        self.resolve = resolve
    }

    func controller(_ kind: VcsKind) -> any VcsWorktreeController {
        resolve(kind)
    }

    static let `default` = VcsWorktreeControllerResolver { kind in
        VcsWorktreeControllerFactory.controller(for: kind)
    }
}

private struct VcsWorktreeControllerResolverKey: EnvironmentKey {
    static var defaultValue: VcsWorktreeControllerResolver { .default }
}

extension EnvironmentValues {
    var vcsWorktreeControllerResolver: VcsWorktreeControllerResolver {
        get { self[VcsWorktreeControllerResolverKey.self] }
        set { self[VcsWorktreeControllerResolverKey.self] = newValue }
    }
}
