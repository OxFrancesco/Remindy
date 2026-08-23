import SwiftUI
import TipKit

enum Motion {
    static let press = Animation.easeOut(duration: 0.13)
    static let tooltip = Animation.spring(response: 0.22, dampingFraction: 1)
    static let toast = Animation.spring(response: 0.32, dampingFraction: 0.9)
    static let calendar = Animation.spring(response: 0.36, dampingFraction: 0.86)
    static let reveal = Animation.spring(response: 0.34, dampingFraction: 0.92)

    static func weekStagger(row: Int) -> Animation {
        calendar.delay(Double(row) * 0.04)
    }
}

enum Symbols {
    static var nfc: String {
        if #available(iOS 18.0, *) { "nfc" } else { "wave.3.right" }
    }
}

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

struct HistoryCalendarTip: Tip {
    var id: String { "history-calendar" }

    var title: Text {
        Text("History")
    }

    var message: Text {
        Text("Open the calendar to see every tag tap and completed reminder.")
    }

    var image: Image {
        Image(systemName: "calendar")
    }
}

struct HistoryTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CalendarFlipGlyph()
                    .font(.title2)
                    .frame(width: 32, height: 32)
                configuration.title
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            if let message = configuration.message {
                message
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 228, alignment: .leading)
    }
}

private struct CalendarFlip {
    var angle: Double = 0
    var scale: CGFloat = 1
}

struct CalendarFlipGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = 0

    var body: some View {
        let skipMotion = reduceMotion
        Image(systemName: "calendar")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.accentColor)
            .keyframeAnimator(
                initialValue: CalendarFlip(),
                trigger: trigger
            ) { content, value in
                content
                    .rotation3DEffect(
                        .degrees(skipMotion ? 0 : value.angle),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.7
                    )
                    .scaleEffect(skipMotion ? 1 : value.scale)
            } keyframes: { _ in
                KeyframeTrack(\.angle) {
                    CubicKeyframe(-68, duration: 0.14)
                    CubicKeyframe(10, duration: 0.12)
                    CubicKeyframe(0, duration: 0.14)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.08, duration: 0.14)
                    CubicKeyframe(0.97, duration: 0.12)
                    CubicKeyframe(1, duration: 0.14)
                }
            }
            .accessibilityHidden(true)
            .onAppear(perform: play)
    }

    private func play() {
        guard !reduceMotion else { return }
        trigger += 1
    }
}
