import SwiftUI

struct ProjectRow: View {
    let project: Project
    let selected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(project.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? .white : MuxyTheme.text)
                .lineLimit(1)

            Text(project.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(size: 10))
                .foregroundStyle(selected ? .white.opacity(0.65) : MuxyTheme.textDim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(background, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Remove Project", role: .destructive, action: onRemove)
        }
    }

    private var background: some ShapeStyle {
        if selected { return AnyShapeStyle(MuxyTheme.accent) }
        if hovered { return AnyShapeStyle(MuxyTheme.hover) }
        return AnyShapeStyle(.clear)
    }
}
