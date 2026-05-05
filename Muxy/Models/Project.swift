import Foundation

struct Project: Identifiable, Codable, Hashable {
    // swiftlint:disable:next force_unwrapping
    static let scratchID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    let id: UUID
    var name: String
    var path: String
    var sortOrder: Int
    var createdAt: Date
    var icon: String?
    var logo: String?
    var iconColor: String?
    var preferredWorktreeParentPath: String?

    init(id: UUID = UUID(), name: String, path: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.path = path
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.icon = nil
        self.logo = nil
        self.iconColor = nil
        self.preferredWorktreeParentPath = nil
    }

    var pathExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
