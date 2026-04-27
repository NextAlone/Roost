import Foundation
import MuxyShared
import Testing

@Suite("WorkspaceStatus")
struct WorkspaceStatusTests {
    @Test("Codable round-trips all cases")
    func codableRoundTrip() throws {
        let original = WorkspaceStatus.allCases
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([WorkspaceStatus].self, from: data)
        #expect(decoded == original)
    }

    @Test("raw values are stable")
    func rawValuesStable() {
        #expect(WorkspaceStatus.clean.rawValue == "clean")
        #expect(WorkspaceStatus.dirty.rawValue == "dirty")
        #expect(WorkspaceStatus.conflicted.rawValue == "conflicted")
        #expect(WorkspaceStatus.unknown.rawValue == "unknown")
    }

    @Test("conflicted dominates dirty in merge")
    func conflictedDominates() {
        #expect(WorkspaceStatus.conflicted.dominates(.dirty))
        #expect(WorkspaceStatus.conflicted.dominates(.clean))
        #expect(WorkspaceStatus.dirty.dominates(.clean))
        #expect(!WorkspaceStatus.clean.dominates(.dirty))
    }
}
