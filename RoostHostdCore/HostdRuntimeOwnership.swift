import Foundation

public enum HostdRuntimeOwnership: String, Sendable, Codable {
    case appOwnedMetadataOnly
    case hostdOwnedProcess
}
