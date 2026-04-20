import AppKit

/// Catalogs editors / IDEs we can hand a project directory off to, and
/// returns the subset that's actually installed on disk. Uses
/// LaunchServices (`urlForApplication(withBundleIdentifier:)`) so we don't
/// hardcode `/Applications/...` paths, which breaks for homebrew-cask
/// installs or users with custom layouts.
enum IDEOpener {
    struct Candidate {
        let name: String
        let bundleID: String
    }

    static let allCandidates: [Candidate] = [
        Candidate(name: "Cursor",              bundleID: "com.todesktop.230313mzl4w4u92"),
        Candidate(name: "Visual Studio Code",  bundleID: "com.microsoft.VSCode"),
        Candidate(name: "Windsurf",            bundleID: "com.exafunction.windsurf"),
        Candidate(name: "Zed",                 bundleID: "dev.zed.Zed"),
        Candidate(name: "Xcode",               bundleID: "com.apple.dt.Xcode"),
        Candidate(name: "Sublime Text",        bundleID: "com.sublimetext.4"),
        Candidate(name: "IntelliJ IDEA",       bundleID: "com.jetbrains.intellij"),
        Candidate(name: "IntelliJ IDEA CE",    bundleID: "com.jetbrains.intellij.ce"),
        Candidate(name: "PyCharm",             bundleID: "com.jetbrains.pycharm"),
        Candidate(name: "PyCharm CE",          bundleID: "com.jetbrains.pycharm.ce"),
        Candidate(name: "RubyMine",            bundleID: "com.jetbrains.RubyMine"),
        Candidate(name: "GoLand",              bundleID: "com.jetbrains.goland"),
        Candidate(name: "WebStorm",            bundleID: "com.jetbrains.WebStorm"),
        Candidate(name: "CLion",               bundleID: "com.jetbrains.CLion"),
        Candidate(name: "Android Studio",      bundleID: "com.google.android.studio"),
        Candidate(name: "Nova",                bundleID: "com.panic.Nova"),
        Candidate(name: "TextMate",            bundleID: "com.macromates.TextMate"),
    ]

    /// Subset of `allCandidates` that LaunchServices can resolve to an
    /// actual bundle URL on this machine. Probed fresh every call — cheap
    /// and keeps the menu honest when the user installs/uninstalls things
    /// at runtime.
    static func installed() -> [(Candidate, URL)] {
        allCandidates.compactMap { c in
            guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: c.bundleID
            ) else { return nil }
            return (c, url)
        }
    }

    /// Hand `directory` off to the app at `appURL`. Errors are logged but
    /// not surfaced as alerts — LaunchServices handles codesign / quarantine
    /// prompts on its own.
    static func open(directory: String, with appURL: URL) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: directory)],
            withApplicationAt: appURL,
            configuration: cfg
        ) { _, err in
            if let err = err {
                NSLog("[Roost] openIDE failed: %@", err.localizedDescription)
            }
        }
    }
}
