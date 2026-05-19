import Foundation

struct CursorProvider: AIProviderIntegration {
    let id = "cursor"
    let displayName = "Cursor CLI"
    let socketTypeKey = "cursor_hook"
    let iconName = "cursor"
    let executableNames = ["cursor-agent", "cursor"]
}
