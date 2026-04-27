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

extension JjProcessRunner {
    private static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    public static func resolveExecutable() -> String? {
        for directory in searchPaths {
            let path = "\(directory)/jj"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    public static func run(
        repoPath: String,
        command: [String],
        snapshot: JjSnapshotPolicy,
        atOp: String? = nil
    ) async throws -> JjProcessResult {
        guard let exec = resolveExecutable() else {
            throw JjProcessError.launchFailed("jj not found on PATH")
        }
        let args = buildArguments(
            repoPath: repoPath,
            command: command,
            snapshot: snapshot,
            atOp: atOp
        )
        let env = buildEnvironment(inherited: ProcessInfo.processInfo.environment)
        return try await Task.detached(priority: .userInitiated) {
            try runProcess(executable: exec, arguments: args, environment: env)
        }.value
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> JjProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin
        try? stdin.fileHandleForWriting.close()

        do {
            try process.run()
        } catch {
            throw JjProcessError.launchFailed(String(describing: error))
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return JjProcessResult(
            status: process.terminationStatus,
            stdout: outData,
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

public typealias JjRunFn = @Sendable (
    _ repoPath: String,
    _ command: [String],
    _ snapshot: JjSnapshotPolicy,
    _ atOp: String?
) async throws -> JjProcessResult

extension JjProcessRunner {
    public static func runRaw(
        executable: String,
        arguments: [String]
    ) async throws -> JjProcessResult {
        let env = buildEnvironment(inherited: ProcessInfo.processInfo.environment)
        return try await Task.detached(priority: .userInitiated) {
            try runProcess(executable: executable, arguments: arguments, environment: env)
        }.value
    }
}
