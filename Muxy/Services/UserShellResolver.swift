import Foundation

enum UserShellResolver {
    static func shell(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        accountShell: () -> String? = systemAccountShell
    ) -> String {
        if let shell = accountShell(), !shell.isEmpty {
            return shell
        }
        if let shell = environment["SHELL"], !shell.isEmpty {
            return shell
        }
        return "/bin/zsh"
    }

    private static func systemAccountShell() -> String? {
        guard let pw = getpwuid(getuid()), let shellPtr = pw.pointee.pw_shell else { return nil }
        return String(cString: shellPtr)
    }
}
