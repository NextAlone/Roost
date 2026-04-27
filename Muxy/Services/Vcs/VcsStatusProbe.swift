import Foundation
import SwiftUI

protocol VcsStatusProbe: Sendable {
    func hasUncommittedChanges(at worktreePath: String) async -> Bool
}

enum VcsStatusProbeFactory {
    static func probe(for kind: VcsKind) -> any VcsStatusProbe {
        switch kind {
        case .git:
            return GitStatusProbe()
        case .jj:
            return JjStatusProbe()
        }
    }
}

struct VcsStatusProbeResolver: Sendable {
    private let resolve: @Sendable (VcsKind) -> any VcsStatusProbe

    init(_ resolve: @escaping @Sendable (VcsKind) -> any VcsStatusProbe) {
        self.resolve = resolve
    }

    func probe(_ kind: VcsKind) -> any VcsStatusProbe {
        resolve(kind)
    }

    static let `default` = VcsStatusProbeResolver { kind in
        VcsStatusProbeFactory.probe(for: kind)
    }
}

private struct VcsStatusProbeResolverKey: EnvironmentKey {
    static var defaultValue: VcsStatusProbeResolver { .default }
}

extension EnvironmentValues {
    var vcsStatusProbeResolver: VcsStatusProbeResolver {
        get { self[VcsStatusProbeResolverKey.self] }
        set { self[VcsStatusProbeResolverKey.self] = newValue }
    }
}
