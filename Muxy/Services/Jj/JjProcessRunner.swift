import Foundation

public enum JjSnapshotPolicy: Sendable {
    case ignore
    case allow
}

public struct JjProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: String
}

public enum JjProcessError: Error, Sendable {
    case launchFailed(String)
    case nonZeroExit(status: Int32, stderr: String)
}

public enum JjProcessRunner {
    public static let allowedInheritedKeys: Set<String> = [
        "HOME", "PATH", "USER", "LOGNAME", "TMPDIR", "JJ_CONFIG",
    ]

    public static func buildEnvironment(inherited: [String: String]) -> [String: String] {
        var env: [String: String] = [:]
        for (key, value) in inherited where allowedInheritedKeys.contains(key) {
            env[key] = value
        }
        env["LANG"] = "C.UTF-8"
        env["LC_ALL"] = "C.UTF-8"
        env["NO_COLOR"] = "1"
        if env["PATH"] == nil {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
        return env
    }

    public static func buildArguments(
        repoPath: String,
        command: [String],
        snapshot: JjSnapshotPolicy,
        atOp: String?
    ) -> [String] {
        var args: [String] = ["--repository", repoPath, "--no-pager", "--color=never"]
        if snapshot == .ignore {
            args.append("--ignore-working-copy")
        }
        if let atOp {
            args.append(contentsOf: ["--at-op", atOp])
        }
        args.append(contentsOf: command)
        return args
    }
}
