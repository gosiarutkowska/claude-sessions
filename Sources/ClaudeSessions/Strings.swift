import Foundation

/// Polish and English UI text. The language comes from the "lang" setting: "pl", "en" or "system"
/// (the system's preferred language if it is Polish, English otherwise).
enum L {
    static var isPolish: Bool {
        switch UserDefaults.standard.string(forKey: "lang") ?? "system" {
        case "pl": return true
        case "en": return false
        default: return Locale.preferredLanguages.first?.hasPrefix("pl") ?? false
        }
    }

    static func t(_ pl: String, _ en: String) -> String { isPolish ? pl : en }

    static var appTitle: String { t("Sesje Claude — terminal", "Claude sessions — terminal") }
    static var archive: String { t("Archiwum", "Archive") }
    static var backToActive: String { t("Wróć do aktywnych", "Back to active") }
    static var refresh: String { t("Odśwież", "Refresh") }
    static var light: String { t("Jasny motyw", "Light theme") }
    static var dark: String { t("Ciemny motyw", "Dark theme") }
    static var system: String { t("Motyw jak w systemie", "Match the system") }
    static var language: String { t("Język: polski / angielski / jak w systemie", "Language: Polish / English / system") }
    static var intro: String { t("Proste zarządzanie Twoimi sesjami Claude.", "Simple management of your Claude sessions.") }
    static var introArchive: String {
        t("Archiwum. Rozmowy zostają na dysku, możesz je przywrócić.",
          "Archive. Conversations stay on disk, you can restore them.")
    }
    static var all: String { t("wszystkie", "all") }
    static var when: String { t("kiedy", "when") }
    static var session: String { t("sesja", "session") }
    static var project: String { t("projekt", "project") }
    static var searchPrompt: String { t("szukaj w tytułach i folderach", "search titles and folders") }
    static var search: String { t("Szukaj", "Search") }
    static var closeSearch: String { t("Zamknij szukanie", "Close search") }
    static var open: String { t("otwarta", "open") }
    static var rename: String { t("Zmień tytuł", "Rename") }
    static var saveTitle: String { t("Zapisz tytuł (Enter)", "Save title (Enter)") }
    static var copy: String { t("Kopiuj polecenie wznowienia", "Copy the resume command") }
    static var copied: String { t("Skopiowane", "Copied") }
    static var toArchive: String { t("Do archiwum", "Archive") }
    static var restore: String { t("Przywróć na listę", "Restore") }
    static var resume: String { t("Wznów w: \(TerminalApp.preferred.name)", "Resume in \(TerminalApp.preferred.name)") }
    static var goToWindow: String { t("Przejdź do okna", "Go to its window") }
    static func originalTitle(_ s: String) -> String { t("Tytuł Claude Code: \(s)", "Claude Code's title: \(s)") }
    static func noMatch(_ q: String) -> String { t("Nic nie pasuje do „\(q)”.", "Nothing matches “\(q)”.") }
    static var archiveEmpty: String { t("Archiwum jest puste.", "The archive is empty.") }
    static var noSessions: String { t("Brak sesji.", "No sessions.") }
    static var today: String { t("'dziś' HH:mm", "'today' HH:mm") }
    static var yesterday: String { t("'wczoraj' HH:mm", "'yesterday' HH:mm") }
    static var locale: Locale { Locale(identifier: isPolish ? "pl_PL" : "en_GB") }
    static var archiveQ: String { t("Przenieść sesję do archiwum?", "Move the session to the archive?") }
    static func archiveInfo(_ title: String, _ project: String) -> String {
        t("„\(title)” (\(project))\n\nZniknie z listy. Rozmowa zostaje na dysku: znajdziesz ją w archiwum i możesz ją przywrócić albo wznowić.",
          "“\(title)” (\(project))\n\nIt disappears from the list. The conversation stays on disk: find it in the archive to restore or resume it.")
    }
    static var archiveButton: String { t("Archiwizuj", "Archive") }
    static var cancel: String { t("Anuluj", "Cancel") }
    static var alreadyOpen: String { t("Ta sesja jest już otwarta", "This session is already open") }
    static func alreadyOpenInfo(_ where_: String) -> String {
        t("Działa w innym oknie (\(where_)). Nie otwieram jej drugi raz.",
          "It is running in another window (\(where_)). Not opening it a second time.")
    }
}
