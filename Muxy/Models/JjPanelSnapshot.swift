import Foundation
import MuxyShared

struct JjPanelSnapshot: Sendable {
    let show: JjShowOutput
    let parentDiff: [JjStatusEntry]
    let status: JjStatus
}
