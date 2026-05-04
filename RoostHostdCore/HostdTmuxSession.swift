import Foundation

public enum HostdTmuxSessionName {
    public static func name(for id: UUID) -> String {
        "roost-\(id.uuidString.lowercased())"
    }
}

public protocol HostdTmuxControlling: Sendable {
    func launch(sessionName: String, workspacePath: String, command: String, environment: [String: String]) async throws
    func hasSession(named sessionName: String) async -> Bool
    func killSession(named sessionName: String) async throws
}

public struct HostdTmuxController: HostdTmuxControlling {
    private let executableName: String

    public init(executableName: String = "tmux") {
        self.executableName = executableName
    }

    static func searchPath(environment: [String: String]) -> String {
        joinedUnique(commonPathEntries(environment: environment) + inheritedPathEntries(environment: environment))
    }

    public func launch(
        sessionName: String,
        workspacePath: String,
        command: String,
        environment: [String: String]
    ) async throws {
        let arguments = Self.launchArguments(
            sessionName: sessionName,
            workspacePath: workspacePath,
            command: command,
            environment: environment
        )
        let result = try await run(arguments: arguments, environment: environment)
        guard result.status == 0 else {
            throw HostdProcessRegistryError.tmuxCommandFailed(
                operation: "launch",
                status: result.status,
                message: result.errorMessage
            )
        }
    }

    static func launchArguments(
        sessionName: String,
        workspacePath: String,
        command: String,
        environment: [String: String]
    ) -> [String] {
        var arguments = ["new-session", "-d", "-s", sessionName, "-c", workspacePath]
        for key in environment.keys.sorted() {
            guard key != "TERM" else { continue }
            guard let value = environment[key] else { continue }
            arguments.append(contentsOf: ["-e", "\(key)=\(value)"])
        }
        arguments.append(contentsOf: ["--", command])
        arguments.append(contentsOf: roostSessionOptionArguments(sessionName: sessionName))
        return arguments
    }

    public func hasSession(named sessionName: String) async -> Bool {
        guard let result = try? await run(arguments: ["has-session", "-t", sessionName], environment: [:]) else {
            return false
        }
        return result.status == 0
    }

    public func killSession(named sessionName: String) async throws {
        let result = try await run(arguments: ["kill-session", "-t", sessionName], environment: [:])
        guard result.status == 0 || result.errorMessage.contains("can't find session") else {
            throw HostdProcessRegistryError.tmuxCommandFailed(
                operation: "kill",
                status: result.status,
                message: result.errorMessage
            )
        }
    }

    private func run(arguments: [String], environment: [String: String]) async throws -> HostdTmuxCommandResult {
        let executableName = executableName
        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executableName] + arguments
            process.environment = Self.mergedEnvironment(environment)

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                throw HostdProcessRegistryError.tmuxUnavailable(message: error.localizedDescription)
            }
            process.waitUntilExit()

            let stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let outputText = String(decoding: stdout, as: UTF8.self)
            let errorText = String(decoding: stderr, as: UTF8.self)
            if process.terminationStatus == 127 {
                throw HostdProcessRegistryError.tmuxUnavailable(message: "\(executableName) not found on PATH")
            }
            return HostdTmuxCommandResult(
                status: process.terminationStatus,
                output: outputText,
                error: errorText
            )
        }.value
    }

    private static func mergedEnvironment(_ environment: [String: String]) -> [String: String] {
        var merged = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            merged[key] = value
        }
        merged["PATH"] = searchPath(environment: merged)
        return merged
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
            "/usr/local/sbin",
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

    private static func roostSessionOptionArguments(sessionName: String) -> [String] {
        [
            ";", "set-option", "-gq", "terminal-features[100]", "xterm-256color:RGB",
            ";", "set-option", "-gq", "terminal-features[101]", "xterm-ghostty:RGB",
            ";", "set-option", "-gq", "terminal-features[102]", "ghostty*:RGB",
            ";", "set-option", "-t", sessionName, "mouse", "on",
            ";", "set-option", "-t", sessionName, "status", "off",
            ";", "set-option", "-t", sessionName, "prefix", "None",
            ";", "set-option", "-t", sessionName, "prefix2", "None",
            ";", "bind-key", "-T", "root", "WheelUpPane", rootWheelUpBinding,
            ";", "bind-key", "-T", "copy-mode", "WheelUpPane", "send-keys", "-X", "-N", "1", "scroll-up",
            ";", "bind-key", "-T", "copy-mode", "WheelDownPane", "send-keys", "-X", "-N", "1", "scroll-down",
            ";", "bind-key", "-T", "copy-mode-vi", "WheelUpPane", "send-keys", "-X", "-N", "1", "scroll-up",
            ";", "bind-key", "-T", "copy-mode-vi", "WheelDownPane", "send-keys", "-X", "-N", "1", "scroll-down",
        ]
    }

    private static let rootWheelUpBinding =
        ##"if-shell -F "#{||:#{alternate_on},#{pane_in_mode},#{mouse_any_flag}}" "##
            + ##""send-keys -M" "copy-mode -e; send-keys -X -N 1 scroll-up""##
}

private struct HostdTmuxCommandResult: Sendable {
    let status: Int32
    let output: String
    let error: String

    var errorMessage: String {
        let text = error.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return output.trimmingCharacters(in: .whitespacesAndNewlines) }
        return text
    }
}
