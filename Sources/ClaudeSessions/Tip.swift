import SwiftUI

/// Tooltip in the app's own style: a small ink label with sharp corners that fades in next to the icon after a
/// short pause, instead of the system's yellow-ish box that takes a second and a half to show.
struct Tip: ViewModifier {
    let text: String
    var below = false
    var trailing = false        // for icons at the window's right edge: the label grows to the left
    @State private var shown = false
    @State private var pending: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                pending?.cancel()
                if inside {
                    let w = DispatchWorkItem { withAnimation(.easeOut(duration: 0.14)) { shown = true } }
                    pending = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
                } else {
                    withAnimation(.easeIn(duration: 0.08)) { shown = false }
                }
            }
            .overlay(alignment: below ? (trailing ? .bottomTrailing : .bottom) : (trailing ? .topTrailing : .top)) {
                if shown && !text.isEmpty {
                    VStack(alignment: trailing ? .trailing : .center, spacing: 0) {
                        if below { notch.rotationEffect(.degrees(180)).padding(.trailing, trailing ? 7 : 0) }
                        Text(text)
                            .font(.system(size: 11, weight: .regular))
                            .tracking(0.2)
                            .foregroundStyle(Ink.vellum)
                            .lineLimit(1)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Ink.ink)
                        if !below { notch.padding(.trailing, trailing ? 7 : 0) }
                    }
                    .fixedSize()
                    .offset(y: below ? 34 : -34)
                    .transition(.opacity.combined(with: .offset(y: below ? -3 : 3)))
                    .allowsHitTesting(false)
                }
            }
    }

    /// The little triangle pointing at the icon.
    private var notch: some View {
        Path { p in
            p.move(to: .zero); p.addLine(to: CGPoint(x: 8, y: 0)); p.addLine(to: CGPoint(x: 4, y: 4)); p.closeSubpath()
        }
        .fill(Ink.ink).frame(width: 8, height: 4)
    }
}

extension View {
    func tip(_ text: String, below: Bool = false, trailing: Bool = false) -> some View {
        modifier(Tip(text: text, below: below, trailing: trailing))
    }
}
