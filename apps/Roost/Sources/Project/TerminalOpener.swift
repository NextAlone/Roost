import AppKit

/// Sister of `IDEOpener`. Catalogs terminal emulators we can hand a
/// directory off to and returns the installed subset.
enum TerminalOpener {
    struct Candidate {
        let name: String
        let bundleID: String
    }

    /// Order matters: shown in the menu top-down. Ghostty first since
    /// Roost embeds libghostty anyway.
    static let allCandidates: [Candidate] = [
        Candidate(name: "Ghostty",       bundleID: "com.mitchellh.ghostty"),
        Candidate(name: "iTerm",         bundleID: "com.googlecode.iterm2"),
        Candidate(name: "WezTerm",       bundleID: "com.github.wez.wezterm"),
        Candidate(name: "Alacritty",     bundleID: "org.alacritty"),
        Candidate(name: "Kitty",         bundleID: "net.kovidgoyal.kitty"),
        Candidate(name: "Warp",          bundleID: "dev.warp.Warp-Stable"),
        Candidate(name: "Hyper",         bundleID: "co.zeit.hyper"),
        Candidate(name: "Terminal.app",  bundleID: "com.apple.Terminal"),
    ]

    static func installed() -> [(Candidate, URL)] {
        allCandidates.compactMap { c in
            guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: c.bundleID
            ) else { return nil }
            return (c, url)
        }
    }

    static func open(directory: String, with appURL: URL) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: directory)],
            withApplicationAt: appURL,
            configuration: cfg
        ) { _, err in
            if let err = err {
                NSLog("[Roost] openTerminal failed: %@", err.localizedDescription)
            }
        }
    }
}
