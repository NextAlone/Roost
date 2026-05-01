import Foundation
import Testing

@testable import Roost

@Suite("Application support storage")
struct ApplicationSupportStorageTests {
    @Test("shared storage directory uses Roost")
    func storageDirectoryUsesRoost() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-storage-tests")
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }

        let directory = MuxyFileStorage.appSupportDirectory(baseDirectory: base)

        #expect(directory.path == base.appendingPathComponent("Roost").path)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }
}
