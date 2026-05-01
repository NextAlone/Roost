import Foundation

enum JjSnapshotPolicy: Sendable {
    case ignore
    case allow
}

struct JjProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: String
}

enum JjProcessError: Error, Sendable {
    case launchFailed(String)
    case nonZeroExit(status: Int32, stderr: String)
}

enum JjProcessRunner {
    static let allowedInheritedKeys: Set<String> = [
        "HOME", "PATH", "USER", "LOGNAME", "TMPDIR", "JJ_CONFIG",
    ]

    static func buildEnvironment(inherited: [String: String]) -> [String: String] {
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

    static func buildArguments(
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

    static func resolveExecutable() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let override = env["ROOST_JJ_PATH"], FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        var dynamicPaths: [String] = []
        if let home = env["HOME"], !home.isEmpty {
            dynamicPaths.append("\(home)/.nix-profile/bin")
            dynamicPaths.append("\(home)/.local/bin")
            dynamicPaths.append("\(home)/.cargo/bin")
        }
        if let user = env["USER"], !user.isEmpty {
            dynamicPaths.append("/etc/profiles/per-user/\(user)/bin")
        }
        dynamicPaths.append("/run/current-system/sw/bin")
        dynamicPaths.append("/nix/var/nix/profiles/default/bin")

        for directory in dynamicPaths + searchPaths {
            let path = "\(directory)/jj"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func run(
        repoPath: String,
        command: [String],
        snapshot: JjSnapshotPolicy,
        atOp: String? = nil
    ) async throws -> JjProcessResult {
        guard let exec = resolveExecutable() else {
            throw JjProcessError.launchFailed("jj not found on PATH")
        }
        return try await runResolved(
            executable: exec,
            repoPath: repoPath,
            command: command,
            snapshot: snapshot,
            atOp: atOp
        )
    }

    static func runResolved(
        executable: String,
        repoPath: String,
        command: [String],
        snapshot: JjSnapshotPolicy,
        atOp: String? = nil
    ) async throws -> JjProcessResult {
        let args = buildArguments(
            repoPath: repoPath,
            command: command,
            snapshot: snapshot,
            atOp: atOp
        )
        let env = buildEnvironment(inherited: ProcessInfo.processInfo.environment)
        return try await Task.detached(priority: .userInitiated) {
            try runProcess(
                executable: executable,
                arguments: args,
                environment: env,
                currentDirectory: repoPath
            )
        }.value
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: String? = nil
    ) throws -> JjProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

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

typealias JjRunFn = @Sendable (
    _ repoPath: String,
    _ command: [String],
    _ snapshot: JjSnapshotPolicy,
    _ atOp: String?
) async throws -> JjProcessResult

extension JjProcessRunner {
    static func runRaw(
        executable: String,
        arguments: [String],
        currentDirectory: String? = nil
    ) async throws -> JjProcessResult {
        let env = buildEnvironment(inherited: ProcessInfo.processInfo.environment)
        return try await Task.detached(priority: .userInitiated) {
            try runProcess(
                executable: executable,
                arguments: arguments,
                environment: env,
                currentDirectory: currentDirectory
            )
        }.value
    }
}
