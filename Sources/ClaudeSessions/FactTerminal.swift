import SwiftUI

/// A little Claude Code conversation on loop: a prompt is typed, a tool call runs, a random fun fact comes back
/// (uselessfacts.jsph.pl, free, no key), then the next prompt starts being typed.
@MainActor
final class FactFeed: ObservableObject {
    struct Line: Identifiable { let id = UUID(); let kind: Kind; var text: String }
    enum Kind { case prompt, tool, result }

    @Published var lines: [Line] = []
    @Published var typing = ""              // the prompt being typed right now, after "> "
    private var task: Task<Void, Never>?

    private static let prompts = [
        "tell me something I don't know", "surprise me", "one more fact?", "what's a weird one?",
        "give me a fun fact before standup", "anything interesting today?",
    ]
    private static let offline = [
        "Honey never spoils: archaeologists have eaten 3000-year-old honey from Egyptian tombs.",
        "Octopuses have three hearts and blue blood.",
        "A day on Venus is longer than its year.",
        "The first computer bug was a real moth, found in a Harvard Mark II relay in 1947.",
        "Bananas are berries, strawberries are not.",
    ]

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            var prompt = Self.prompts.randomElement()!
            while !Task.isCancelled {
                guard let self else { return }
                await self.type(prompt)
                try? await Task.sleep(nanoseconds: 400_000_000)
                self.lines.append(Line(kind: .prompt, text: prompt))
                self.typing = ""
                self.lines.append(Line(kind: .tool, text: "fact · random()"))
                let fact = await Self.fetch()
                try? await Task.sleep(nanoseconds: 700_000_000)
                self.lines.append(Line(kind: .result, text: fact))
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                // start typing the next question, then keep only that exchange on screen
                prompt = Self.prompts.filter { $0 != prompt }.randomElement()!
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                self.lines.removeAll()
            }
        }
    }

    private func type(_ text: String) async {
        for ch in text {
            typing.append(ch)
            try? await Task.sleep(nanoseconds: UInt64.random(in: 35_000_000...110_000_000))
        }
    }

    private static func fetch() async -> String {
        guard let url = URL(string: "https://uselessfacts.jsph.pl/api/v2/facts/random?language=en") else {
            return offline.randomElement()!
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["text"] as? String, text.count < 200 {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "`", with: "'")
        }
        return offline.randomElement()!
    }
}

/// A dark terminal strip across the top of the app, the one coloured thing in it.
struct FactTerminal: View {
    /// Folded down to a thin strip with only the green chevron (and the window's traffic lights).
    @AppStorage("terminalCollapsed") private var collapsed = false
    static let green = Color(red: 0x6C / 255, green: 0xCB / 255, blue: 0x5F / 255)
    static func height(collapsed: Bool) -> CGFloat { collapsed ? 34 : 150 }
    @StateObject private var feed = FactFeed()
    @State private var cursorOn = true
    private let blink = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    private let fg = Color(red: 0xF2 / 255, green: 0xEF / 255, blue: 0xE8 / 255)
    private let dim = Color(red: 0xA8 / 255, green: 0xA4 / 255, blue: 0x9C / 255)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if !collapsed { screen }
            Button { withAnimation(.easeInOut(duration: 0.22)) { collapsed.toggle() } } label: {
                Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.green)
                    .frame(width: 28, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tip(collapsed ? L.t("Pokaż terminal", "Show the terminal") : L.t("Schowaj terminal", "Hide the terminal"),
                 below: collapsed, trailing: true)
            .padding(.trailing, 20).padding(.bottom, collapsed ? 5 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .background(Ink.term)
        .onAppear { feed.start() }
        .onReceive(blink) { _ in cursorOn.toggle() }
    }

    private var screen: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(feed.lines) { line in
                    switch line.kind {
                    case .prompt: Text("> " + line.text).foregroundStyle(fg)
                    case .tool:
                        HStack(spacing: 6) {
                            Circle().fill(fg).frame(width: 7, height: 7)
                            Text(line.text).foregroundStyle(fg)
                        }
                    case .result: Text("  " + line.text).foregroundStyle(dim).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !feed.lines.isEmpty { Spacer().frame(height: 6) }
                HStack(spacing: 0) {
                    Text("> " + feed.typing).foregroundStyle(fg)
                    Rectangle().fill(fg).frame(width: 8, height: 15).opacity(cursorOn ? 1 : 0)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12.5, weight: .regular, design: .monospaced))
            .padding(.horizontal, 28).padding(.top, 34)        // top: clear of the window's traffic lights
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .transition(.opacity)
    }
}
