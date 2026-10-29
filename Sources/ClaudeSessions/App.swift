import AppKit
import Combine
import SwiftUI

/// "Editorial ink on warm vellum": four tones, one font weight, hairlines instead of boxes, no buttons with fills.
enum Ink {
    static let vellum = dyn(0xE8E7E3, dark: 0x141311)
    static let parchment = dyn(0xDDDBD5, dark: 0x1F1E1B)
    static let ink = dyn(0x050200, dark: 0xE8E7E3)
    static let graphite = dyn(0x747472, dark: 0x8E8D89)

    /// One tone per appearance: the dark theme is the same paper-and-ink idea, inverted.
    private static func dyn(_ light: Int, dark: Int) -> Color {
        func c(_ v: Int) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? c(dark) : c(light)
        })
    }
    /// The terminal strip's near-black, also used for the one filled button (Search).
    static let term = Color(red: 0x34 / 255, green: 0x31 / 255, blue: 0x2C / 255)
    static let onTerm = Color(red: 0xE8 / 255, green: 0xE7 / 255, blue: 0xE3 / 255)
    static func font(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
    static let pad: CGFloat = 20
    static let hair: CGFloat = 0.7
}

@main
struct ClaudeSessionsApp: App {
    @StateObject private var store = SessionStore()
    @AppStorage("theme") private var theme = "system"

    var body: some Scene {
        WindowGroup("Sesje Claude") {
            SessionList()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 480)
                .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 760)
    }
}

struct SessionList: View {
    @EnvironmentObject var store: SessionStore
    @State private var query = ""
    @State private var draftQuery = ""
    @AppStorage("terminalCollapsed") private var terminalCollapsed = false
    @State private var project: String?
    @State private var copied: String?
    @State private var showArchive = false
    @State private var editing: String?
    @State private var draft = ""
    @FocusState private var editFocused: Bool
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private var projects: [String] { Array(Set(store.sessions.map(\.project))).sorted() }

    private var shown: [Session] {
        store.sessions.filter { s in
            store.archived.contains(s.id) == showArchive &&
            (project == nil || s.project == project) &&
            (query.isEmpty || store.title(s).localizedCaseInsensitiveContains(query) || s.cwd.localizedCaseInsensitiveContains(query))
        }
        .sorted { a, b in
            func by(_ x: String, _ y: String) -> Bool? {
                let c = x.localizedCaseInsensitiveCompare(y)
                return c == .orderedSame ? nil : (c == .orderedAscending) == sortAscending
            }
            switch sortKey {
            case "project": return by(a.project, b.project) ?? (a.updated > b.updated)   // newest first within a project
            case "title": return by(store.title(a), store.title(b)) ?? (a.updated > b.updated)
            default: return sortAscending ? a.updated < b.updated : a.updated > b.updated
            }
        }
    }

    @AppStorage("sortKey") private var sortKey = "date"
    @AppStorage("sortAscending") private var sortAscending = false

    /// Click a column to sort by it; click it again to flip the order. Dates start newest first, text A→Z.
    private func sortHeader(_ label: String, _ key: String) -> some View {
        Button {
            if sortKey == key { sortAscending.toggle() } else { sortKey = key; sortAscending = key != "date" }
        } label: {
            HStack(spacing: 4) {
                Text(label).foregroundStyle(sortKey == key ? Ink.ink : Ink.graphite)
                if sortKey == key {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down").font(.system(size: 10, weight: .light))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tip(L.t("Sortuj", "Sort"))
    }

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 0
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    FactTerminal().frame(height: FactTerminal.height(collapsed: terminalCollapsed))
                    Section(header: headerBand.padding(.horizontal, inset).background(Ink.vellum)) {
                        VStack(alignment: .leading, spacing: 0) {
                            intro
                            Spacer().frame(height: 40)
                            searchBar
                            filters
                            columnHeader
                            ForEach(shown) { s in row(s) }
                            if shown.isEmpty && !store.loading {
                                Text(empty).font(Ink.font(13)).foregroundStyle(Ink.graphite)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(Ink.pad)
                            }
                            Spacer().frame(height: 60)
                        }
                        .padding(.horizontal, inset)
                    }
                }
                .frame(minHeight: geo.size.height, alignment: .top)
            }
        }
        .background(Ink.vellum)
        .foregroundStyle(Ink.ink)
        .ignoresSafeArea()
        .onAppear { store.refresh() }
        .onReceive(timer) { _ in store.refresh() }
    }

    private var empty: String {
        if !query.isEmpty { return L.noMatch(query) }
        return showArchive ? L.archiveEmpty : L.noSessions
    }

    @AppStorage("theme") private var theme = "system"
    @AppStorage("lang") private var lang = "system"     // read here so the view redraws when it changes
    @AppStorage("terminal") private var terminalChoice = "auto"
    @AppStorage("newTab") private var newTab = false

    /// Stays at the top while scrolling.
    private var headerBand: some View {
        HStack(spacing: 22) {
            Text(L.appTitle).font(Ink.font(13))
            Spacer()
            if store.loading { Text("…").font(Ink.font(13)).foregroundStyle(Ink.graphite) }
            icon("archivebox", showArchive ? L.backToActive : L.archive, below: true) { showArchive.toggle() }
            icon("arrow.clockwise", L.refresh, below: true) { store.refresh() }
            Rectangle().fill(Ink.graphite).frame(width: Ink.hair, height: 16)
            HStack(spacing: 14) {
                themeIcon("sun.max", "light", L.light)
                themeIcon("moon", "dark", L.dark)
                themeIcon("circle.lefthalf.filled", "system", L.system)
            }
            Rectangle().fill(Ink.graphite).frame(width: Ink.hair, height: 16)
            HStack(spacing: 10) {
                langButton("PL", "pl"); langButton("EN", "en"); langButton("A", "system")
            }
            .tip(L.language, below: true, trailing: true)
            Rectangle().fill(Ink.graphite).frame(width: Ink.hair, height: 16)
            terminalMenu
        }
        .padding(.horizontal, Ink.pad)
        .frame(height: 60)
        .background(alignment: .bottom) { hairline }      // behind, so tooltips that drop below stay on top of it
        .background(Ink.parchment)
    }

    private func themeIcon(_ name: String, _ value: String, _ help: String) -> some View {
        Button { theme = value } label: {
            Image(systemName: name).font(.system(size: 13, weight: .light))
                .foregroundStyle(theme == value ? Ink.ink : Ink.graphite)
        }
        .buttonStyle(.plain).tip(help, below: true)
    }

    /// Which terminal → opens sessions in. Only installed ones are listed; "auto" picks the first of them.
    private var terminalMenu: some View {
        Menu {
            Button((terminalChoice == "auto" ? "✓ " : "   ") + L.t("Automatycznie", "Automatic")) { terminalChoice = "auto" }
            Divider()
            ForEach(TerminalApp.installedApps) { t in
                Button((terminalChoice == t.rawValue ? "✓ " : "   ") + t.name) { terminalChoice = t.rawValue }
            }
            Divider()
            Button((!newTab ? "✓ " : "   ") + L.t("Otwieraj w nowym oknie", "Open in a new window")) { newTab = false }
            Button((newTab ? "✓ " : "   ") + L.t("Otwieraj jako nową kartę", "Open as a new tab")
                   + (TerminalApp.preferred.supportsTabs ? "" : L.t(" (ten terminal: zawsze okno)", " (this terminal: always a window)"))) {
                newTab = true
            }
        } label: {
            Text(TerminalApp.preferred.name).font(Ink.font(11)).tracking(0.5).foregroundStyle(Ink.ink)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .tip(L.t("Terminal, w którym otwierają się sesje", "The terminal sessions open in"), below: true, trailing: true)
    }

    private func langButton(_ label: String, _ value: String) -> some View {
        Button { lang = value } label: {
            Text(label).font(Ink.font(11)).tracking(0.5)
                .foregroundStyle(lang == value ? Ink.ink : Ink.graphite)
        }
        .buttonStyle(.plain)
    }

    private var intro: some View {
        Text(showArchive ? L.introArchive : L.intro)
            .font(.system(size: 30, weight: .regular, design: .serif))
            .lineSpacing(2)
            .padding(.horizontal, Ink.pad).padding(.top, 38)
    }

    /// One hairline to type on and a solid Search button; Enter works too. Searching for nothing clears it.
    private var searchBar: some View {
        HStack(alignment: .bottom, spacing: 16) {
            Spacer()
            HStack(spacing: 8) {
                TextField("", text: $draftQuery, prompt: Text(L.searchPrompt).foregroundColor(Ink.graphite))
                    .textFieldStyle(.plain).font(Ink.font(14))
                    .onSubmit { query = draftQuery }
                if !query.isEmpty {
                    Button { draftQuery = ""; query = "" } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .light)).foregroundStyle(Ink.graphite)
                    }
                    .buttonStyle(.plain).tip(L.closeSearch)
                }
            }
            .padding(.bottom, 7)
            .frame(width: 240)
            .background(alignment: .bottom) { hairline }
            Button { query = draftQuery } label: {
                Text(L.search).font(Ink.font(13)).foregroundStyle(Ink.onTerm)
                    .padding(.horizontal, 22).frame(height: 32)
                    .background(Ink.term)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Ink.pad).padding(.bottom, 30)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                filter(L.all, nil)
                ForEach(projects, id: \.self) { filter($0, $0) }
            }
            .padding(.horizontal, Ink.pad)
        }
        .padding(.bottom, 26)
    }

    private func filter(_ label: String, _ value: String?) -> some View {
        Button { project = value } label: {
            Text(label).font(Ink.font(13))
                .foregroundStyle(project == value ? Ink.ink : Ink.graphite)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    if project == value { Rectangle().fill(Ink.ink).frame(height: Ink.hair) }
                }
        }
        .buttonStyle(.plain)
    }

    private var columnHeader: some View {
        HStack(spacing: 18) {
            sortHeader(L.when, "date").frame(width: 110, alignment: .leading)
            sortHeader(L.session, "title").frame(maxWidth: .infinity, alignment: .leading)
            sortHeader(L.project, "project").frame(width: 130, alignment: .leading)
            Spacer().frame(width: 160)
        }
        .font(Ink.font(13)).foregroundStyle(Ink.graphite)
        .padding(.horizontal, Ink.pad).padding(.bottom, 12)
        .background(alignment: .bottom) { hairline }
    }

    @ViewBuilder
    private func row(_ s: Session) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Text(when(s.updated)).frame(width: 110, alignment: .leading)
            HStack(spacing: 10) {
                if editing == s.id {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain).focused($editFocused)
                        .onSubmit { store.rename(s, draft); editing = nil }
                        .onExitCommand { editing = nil }
                        .padding(.bottom, 2)
                        .background(alignment: .bottom) { hairline }
                } else {
                    Text(store.title(s)).lineLimit(1).truncationMode(.tail)
                        .help(store.titles[s.id] != nil ? L.originalTitle(s.title) : "")
                }
                if s.openPID != nil {
                    Text(L.open).font(Ink.font(11))
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .overlay(Capsule().stroke(Ink.ink, lineWidth: Ink.hair))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(s.project).lineLimit(1).frame(width: 130, alignment: .leading)
            HStack(spacing: 20) {
                icon(editing == s.id ? "checkmark" : "pencil", editing == s.id ? L.saveTitle : L.rename) {
                    if editing == s.id { store.rename(s, draft); editing = nil; return }
                    draft = store.title(s); editing = s.id
                    DispatchQueue.main.async { editFocused = true }
                }
                icon(copied == s.id ? "checkmark" : "doc.on.doc", copied == s.id ? L.copied : L.copy) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(s.resumeCommand, forType: .string)
                    copied = s.id
                }
                icon(showArchive ? "arrow.uturn.backward" : "archivebox",
                     showArchive ? L.restore : L.toArchive) { confirmArchive(s) }
                icon(s.openPID != nil ? "arrow.up.right" : "arrow.right",
                     s.openPID != nil ? L.goToWindow : L.resume, trailing: true) { open(s) }
            }
            .frame(width: 160, alignment: .trailing)
        }
        .font(Ink.font(13))
        .padding(.horizontal, Ink.pad).frame(height: 52)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open(s) }
        .background(alignment: .bottom) { hairline }
    }

    private var hairline: some View { Rectangle().fill(Ink.ink).frame(height: Ink.hair) }

    private func icon(_ name: String, _ help: String, below: Bool = false, trailing: Bool = false,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 15, weight: .light))
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).tip(help, below: below, trailing: trailing)
    }

    private func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = L.locale
        f.dateFormat = Calendar.current.isDateInToday(d) ? L.today
            : Calendar.current.isDateInYesterday(d) ? L.yesterday : "d MMM, HH:mm"
        return f.string(from: d)
    }

    private func confirmArchive(_ s: Session) {
        if showArchive { store.setArchived(s, false); return }
        let a = NSAlert()
        a.messageText = L.archiveQ
        a.informativeText = L.archiveInfo(store.title(s), s.project)
        a.addButton(withTitle: L.archiveButton)
        a.addButton(withTitle: L.cancel).keyEquivalent = "\u{1b}"
        if a.runModal() == .alertFirstButtonReturn { store.setArchived(s, true) }
    }

    /// An open session is never resumed a second time (two processes writing one history breaks it):
    /// focus its window instead, or say where it is.
    private func open(_ s: Session) {
        if s.openPID != nil {
            if let pid = s.openPID, Terminals.focus(pid: pid, tty: s.openTTY) { return }
            let a = NSAlert()
            a.messageText = L.alreadyOpen
            a.informativeText = L.alreadyOpenInfo(s.openTTY ?? "?")
            a.runModal()
            return
        }
        if let note = Terminals.resume(s) {
            let a = NSAlert()
            a.messageText = TerminalApp.preferred.name
            a.informativeText = note
            a.runModal()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { store.refresh() }
    }
}
