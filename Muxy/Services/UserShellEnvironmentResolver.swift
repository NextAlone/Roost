import Foundation

enum UserShellEnvironmentResolver {
    typealias ShellPathRunner = (String, [String: String]) -> String?

    private static let cache = UserShellEnvironmentPathCache()

    static func cachedPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        shell: String = UserShellResolver.shell(),
        runShellPath: ShellPathRunner = runLoginShellPath
    ) -> String {
        cache.value(shell: shell, environment: environment) {
            path(environment: environment, shell: shell, runShellPath: runShellPath)
        }
    }

    static func path(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        shell: String = UserShellResolver.shell(),
        runShellPath: ShellPathRunner = runLoginShellPath
    ) -> String {
        if let resolved = runShellPath(shell, environment).flatMap(normalizedPathLine), !resolved.isEmpty {
            return resolved
        }
        return fallbackPath(environment: environment)
    }

    private static func runLoginShellPath(shell: String, environment: [String: String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", pathCommand(for: shell)]
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        guard waitForExit(process, timeout: 2) else { return nil }
        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func pathCommand(for shell: String) -> String {
        URL(fileURLWithPath: shell).lastPathComponent == "fish"
            ? "string join : $PATH"
            : "printf '%s\\n' \"$PATH\""
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: .now() + timeout) == .success {
            return true
        }

        process.terminate()
        _ = group.wait(timeout: .now() + 1)
        return false
    }

    private static func normalizedPathLine(_ output: String) -> String? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("PATH=") {
                line.removeFirst(5)
            }

            let parts = line.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts.contains(where: { $0.hasPrefix("/") }) else { continue }
            guard parts.allSatisfy({ $0.isEmpty || $0.hasPrefix("/") }) else { continue }
            return joinedUnique(parts)
        }
        return nil
    }

    private static func fallbackPath(environment: [String: String]) -> String {
        joinedUnique(commonPathEntries(environment: environment) + inheritedPathEntries(environment: environment))
    }

    private static func commonPathEntries(environment: [String: String]) -> [String] {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let user = environment["USER"] ?? NSUserName()
        return [
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.nix-profile/bin",
            "/etc/profiles/per-user/\(user)/bin",
            "/run/current-system/sw/bin",
            "/nix/var/nix/profiles/default/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
    }

    private static func inheritedPathEntries(environment: [String: String]) -> [String] {
        environment["PATH"]?.split(separator: ":").map(String.init) ?? []
    }

    private static func joinedUnique(_ entries: [String]) -> String {
        var seen = Set<String>()
        return entries
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
    }
}

private struct UserShellEnvironmentPathCacheKey: Hashable {
    let shell: String
    let path: String
    let home: String
    let user: String
    let logname: String

    init(shell: String, environment: [String: String]) {
        self.shell = shell
        path = environment["PATH"] ?? ""
        home = environment["HOME"] ?? ""
        user = environment["USER"] ?? ""
        logname = environment["LOGNAME"] ?? ""
    }
}

private final class UserShellEnvironmentPathCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UserShellEnvironmentPathCacheKey: String] = [:]

    func value(shell: String, environment: [String: String], resolve: () -> String) -> String {
        let key = UserShellEnvironmentPathCacheKey(shell: shell, environment: environment)

        lock.lock()
        if let value = values[key] {
            lock.unlock()
            return value
        }
        lock.unlock()

        let resolved = resolve()

        lock.lock()
        let value = values[key] ?? resolved
        values[key] = value
        lock.unlock()

        return value
    }
}
