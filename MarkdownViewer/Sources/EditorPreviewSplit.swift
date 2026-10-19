import SwiftUI

/// Source and preview panes side by side with a draggable divider.
///
/// Both panes stay alive in every mode (so the editor keeps its undo stack and
/// the preview keeps its scroll position); switching modes animates the
/// divider to an edge instead of removing views.
struct EditorPreviewSplit<Leading: View, Trailing: View>: View {
    let mode: ViewMode
    @Binding var fraction: Double
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var minPaneWidth: CGFloat = 220

    @State private var dragStartWidth: CGFloat?
    @State private var isHoveringDivider = false

    var body: some View {
        GeometryReader { geometry in
            let total = geometry.size.width
            let leadingWidth = leadingWidth(total: total)

            HStack(spacing: 0) {
                leading
                    .frame(width: leadingWidth)
                    .clipped()
                    .allowsHitTesting(mode != .preview)
                    .accessibilityHidden(mode == .preview)

                Rectangle()
                    .fill(.separator)
                    .frame(width: mode == .split ? 1 : 0)

                trailing
                    .frame(width: max(0, total - leadingWidth - (mode == .split ? 1 : 0)))
                    .clipped()
                    .allowsHitTesting(mode != .source)
                    .accessibilityHidden(mode == .source)
            }
            .overlay(alignment: .topLeading) {
                if mode == .split {
                    dividerHandle(total: total)
                        .offset(x: leadingWidth - 5)
                }
            }
        }
    }

    private func leadingWidth(total: CGFloat) -> CGFloat {
        switch mode {
        case .source: total
        case .preview: 0
        case .split:
            min(max(total * fraction, minPaneWidth), max(minPaneWidth, total - minPaneWidth))
        }
    }

    private func dividerHandle(total: CGFloat) -> some View {
        Capsule()
            .fill(isHoveringDivider || dragStartWidth != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
            .frame(width: 3)
            .padding(.vertical, 6)
            .frame(width: 11)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .pointerStyle(.columnResize)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isHoveringDivider = hovering }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartWidth ?? leadingWidth(total: total)
                        dragStartWidth = start
                        let width = min(max(start + value.translation.width, minPaneWidth), total - minPaneWidth)
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { fraction = width / total }
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .onTapGesture(count: 2) {
                withAnimation(.smooth(duration: 0.3)) { fraction = 0.5 }
            }
            .help("Drag to resize. Double-click to center.")
    }
}
