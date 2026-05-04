enum WindowTitleFormatter {
    static func title(projectName: String?, tabTitle: String?) -> String {
        guard let projectName else { return "Roost" }
        guard let tabTitle, !tabTitle.isEmpty else { return projectName }
        return "\(projectName) — \(tabTitle)"
    }
}
