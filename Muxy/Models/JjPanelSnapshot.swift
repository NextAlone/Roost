import Foundation
import MuxyShared

struct JjPanelSnapshot {
    let show: JjShowOutput
    let parentDiff: [JjStatusEntry]
    let status: JjStatus
    let bookmarks: [JjBookmark]
    let conflicts: [JjConflict]
}
