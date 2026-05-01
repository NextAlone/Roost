import Foundation
import MuxyShared

struct JjPanelSnapshot {
    let show: JjShowOutput
    let status: JjStatus
    let changes: [JjLogEntry]
    let bookmarks: [JjBookmark]
    let conflicts: [JjConflict]
}
