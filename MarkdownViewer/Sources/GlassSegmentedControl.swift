import SwiftUI

/// A segmented control with a Liquid Glass selection thumb.
///
/// Click a segment and the glass thumb slides over to it. Press and drag and
/// the thumb follows the pointer, swelling into a clear glass lens, then snaps
/// to the nearest segment when released.
struct GlassSegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: String
        let systemImage: String
        var id: Value { value }
    }

    @Binding var selection: Value
    let segments: [Segment]

    var segmentWidth: CGFloat = 118
    var height: CGFloat = 32
    private let inset: CGFloat = 3

    /// Transient press/drag state. `@GestureState` resets on its own when the
    /// gesture ends or is cancelled (e.g. the window loses key mid-drag).
    @GestureState private var press: Press?
    @Environment(\.colorScheme) private var colorScheme

    private struct Press: Equatable {
        /// Thumb centre (in track coordinates) while it follows the pointer.
        var center: CGFloat?
    }

    private var isPressed: Bool { press != nil }
    private var dragCenter: CGFloat? { press?.center }

    private var selectedIndex: Int {
        segments.firstIndex { $0.value == selection } ?? 0
    }

    private var trackWidth: CGFloat { segmentWidth * CGFloat(segments.count) }

    private func clampedCenter(_ x: CGFloat) -> CGFloat {
        min(max(x, segmentWidth / 2), trackWidth - segmentWidth / 2)
    }

    private func index(at x: CGFloat) -> Int {
        min(max(Int(x / segmentWidth), 0), segments.count - 1)
    }

    /// The segment currently under the thumb (live while dragging).
    private var highlightedIndex: Int {
        dragCenter.map(index(at:)) ?? selectedIndex
    }

    private var thumbOffset: CGFloat {
        if let dragCenter { return clampedCenter(dragCenter) - segmentWidth / 2 }
        return CGFloat(selectedIndex) * segmentWidth
    }

    var body: some View {
        ZStack(alignment: .leading) {
            thumb
            labels
        }
        .frame(width: trackWidth, height: height - inset * 2)
        .padding(inset)
        // A slightly darker track (like native segmented controls) so the
        // lighter thumb stands out in both appearances.
        .glassEffect(.regular.tint(trackTint), in: .capsule)
        .contentShape(.capsule)
        .gesture(dragGesture)
        .accessibilityRepresentation {
            Picker("View", selection: $selection) {
                ForEach(segments) { segment in
                    Label(segment.title, systemImage: segment.systemImage).tag(segment.value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var trackTint: Color {
        colorScheme == .dark ? .black.opacity(0.35) : .black.opacity(0.09)
    }

    /// Tint that lifts the glass thumb off the track. A clear thumb is nearly
    /// invisible on a dark toolbar, so dark mode gets a brighter fill.
    private var thumbTint: Color {
        colorScheme == .dark ? .white.opacity(isPressed ? 0.16 : 0.26) : .white.opacity(isPressed ? 0.4 : 0.95)
    }

    private var thumb: some View {
        Capsule()
            .fill(.clear)
            .frame(width: segmentWidth, height: height - inset * 2)
            .glassEffect(isPressed ? .clear.tint(thumbTint).interactive() : .regular.tint(thumbTint).interactive(), in: .capsule)
            .overlay {
                // Fine highlight edge so the pill reads as raised glass.
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(colorScheme == .dark ? 0.35 : 0.9), .white.opacity(colorScheme == .dark ? 0.08 : 0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : (isPressed ? 0.18 : 0.12)), radius: isPressed ? 8 : 3, y: isPressed ? 3 : 1)
            .scaleEffect(x: isPressed ? 1.10 : 1, y: isPressed ? 1.22 : 1)
            .offset(x: thumbOffset)
            .animation(dragCenter == nil ? .spring(response: 0.38, dampingFraction: 0.72) : .interactiveSpring(response: 0.18, dampingFraction: 0.86), value: thumbOffset)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .allowsHitTesting(false)
    }

    private var labels: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                Label(segment.title, systemImage: segment.systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: index == highlightedIndex ? .semibold : .medium))
                    .foregroundStyle(index == highlightedIndex ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .frame(width: segmentWidth, height: height - inset * 2)
            }
        }
        .animation(.easeOut(duration: 0.15), value: highlightedIndex)
        .allowsHitTesting(false)
    }

    /// Where the thumb centre should be for a drag value, or nil while the
    /// press has not turned into a drag yet.
    private func thumbCenter(for value: DragGesture.Value) -> CGFloat? {
        let start = value.startLocation.x - inset
        let x = value.location.x - inset
        let startedOnThumb = index(at: start) == selectedIndex
        // Dragging the thumb, or sliding away from the press point, moves the
        // glass with the pointer.
        guard startedOnThumb || abs(value.translation.width) > 4 else { return nil }
        let grabOffset = startedOnThumb ? start - (CGFloat(selectedIndex) + 0.5) * segmentWidth : 0
        return x - grabOffset
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($press) { value, state, _ in
                state = Press(center: thumbCenter(for: value))
            }
            .onEnded { value in
                let target = thumbCenter(for: value).map { index(at: clampedCenter($0)) } ?? index(at: value.location.x - inset)
                if segments.indices.contains(target), segments[target].value != selection {
                    selection = segments[target].value
                }
            }
    }
}

#Preview {
    @Previewable @State var mode: ViewMode = .split
    GlassSegmentedControl(
        selection: $mode,
        segments: ViewMode.allCases.map { .init(value: $0, title: $0.title, systemImage: $0.systemImage) }
    )
    .padding(40)
}
