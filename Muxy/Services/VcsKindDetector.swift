import Foundation

enum VcsKindDetector {
    static func detect(at path: String) -> VcsKind {
        let fm = FileManager.default
        let jjPath = (path as NSString).appendingPathComponent(".jj")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: jjPath, isDirectory: &isDir), isDir.boolValue {
            return .jj
        }
        let gitPath = (path as NSString).appendingPathComponent(".git")
        if fm.fileExists(atPath: gitPath) {
            return .git
        }
        return .default
    }
}
