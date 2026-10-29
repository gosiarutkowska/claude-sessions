import AppKit

/// The terminal apps a session can be resumed in. Each one is driven the way it supports best: AppleScript for
/// iTerm and Terminal (they can also jump to the exact tab of an open session), command-line launchers for the rest.
/// Warp can't be told to run a command, so it opens in the session's folder with the command on the clipboard.
enum TerminalApp: String, CaseIterable, Identifiable {
    case iterm, terminal, ghostty, warp, kitty, wezterm, alacritty

    var id: String { rawValue }

    var name: String {
        switch self {
        case .iterm: "iTerm"
        case .terminal: "Terminal"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        case .kitty: "kitty"
        case .wezterm: "WezTerm"
        case .alacritty: "Alacritty"
        }
    }

    var bundleIDs: [String] {
        switch self {
        case .iterm: ["com.googlecode.iterm2"]
        case .terminal: ["com.apple.Terminal"]
        case .ghostty: ["com.mitchellh.ghostty"]
        case .warp: ["dev.warp.Warp-Stable", "dev.warp.Warp"]
        case .kitty: ["net.kovidgoyal.kitty"]
        case .wezterm: ["com.github.wez.wezterm"]
        case .alacritty: ["org.alacritty", "io.alacritty"]
        }
    }

    var url: URL? {
        bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    var installed: Bool { url != nil }

    static var installedApps: [TerminalApp] { allCases.filter(\.installed) }

    /// Can open a session as a new tab of an already open window (the rest always get a new window).
    var supportsTabs: Bool { [.iterm, .terminal, .wezterm, .warp].contains(self) }

    /// The user's choice: a new tab in the open terminal window instead of a new window.
    static var preferTabs: Bool { UserDefaults.standard.bool(forKey: "newTab") }

    /// The user's choice ("auto" = the first installed one in the order above; Terminal is always there).
    static var preferred: TerminalApp {
        let choice = UserDefaults.standard.string(forKey: "terminal") ?? "auto"
        if let t = TerminalApp(rawValue: choice), t.installed { return t }
        return installedApps.first ?? .terminal
    }
}

enum Terminals {
    /// Opens a new window of the preferred terminal and resumes the session there. Returns a note for the user
    /// when something is left for them to do (Warp: paste the command).
    @discardableResult
    static func resume(_ s: Session) -> String? {
        let app = TerminalApp.preferred
        let tab = TerminalApp.preferTabs && app.supportsTabs
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // keep the window open with a normal shell after Claude Code exits
        let line = "\(s.resumeCommand); exec \(shell) -l"
        switch app {
        case .iterm:
            appleScript("""
            tell application id "com.googlecode.iterm2"
                activate
                if \(tab) and (count of windows) > 0 then
                    tell current window to set t to (create tab with default profile)
                    tell current session of current window to write text "\(escape(s.resumeCommand))"
                else
                    set w to (create window with default profile)
                    tell current session of w to write text "\(escape(s.resumeCommand))"
                end if
            end tell
            """)
        case .terminal:
            // Terminal has no "new tab" command: ⌘T through System Events (asks once for Accessibility), then run
            // the command in that tab. Without the permission it falls back to a new window.
            if tab, isRunning(.terminal), appleScript("""
                tell application id "com.apple.Terminal" to activate
                tell application "System Events" to keystroke "t" using command down
                delay 0.3
                tell application id "com.apple.Terminal" to do script "\(escape(s.resumeCommand))" in selected tab of front window
                return "ok"
                """) == "ok" { break }
            appleScript("""
            tell application id "com.apple.Terminal"
                activate
                do script "\(escape(s.resumeCommand))"
            end tell
            """)
        case .ghostty:
            launch(["open", "-na", app.url!.path, "--args", "--working-directory=\(s.cwd)", "-e", shell, "-lc", line])
        case .kitty:
            launch([app.url!.appendingPathComponent("Contents/MacOS/kitty").path, "--single-instance",
                    "--directory", s.cwd, shell, "-lc", line])
        case .wezterm:
            let bin = app.url!.appendingPathComponent("Contents/MacOS/wezterm").path
            // `cli spawn` adds a tab to the running WezTerm; `start` opens a new window
            launch(tab && isRunning(.wezterm) ? [bin, "cli", "spawn", "--cwd", s.cwd, "--", shell, "-lc", line]
                                              : [bin, "start", "--cwd", s.cwd, "--", shell, "-lc", line])
        case .alacritty:
            launch([app.url!.appendingPathComponent("Contents/MacOS/alacritty").path, "--working-directory", s.cwd,
                    "-e", shell, "-lc", line])
        case .warp:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s.resumeCommand, forType: .string)
            let path = s.cwd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s.cwd
            if let u = URL(string: "warp://action/\(tab ? "new_tab" : "new_window")?path=\(path)") { NSWorkspace.shared.open(u) }
            return L.t("Warp nie pozwala uruchomić polecenia z zewnątrz. Polecenie jest w schowku: wklej je (⌘V) i naciśnij Enter.",
                       "Warp doesn't let other apps run commands. The command is on the clipboard: paste it (⌘V) and press Enter.")
        }
        return nil
    }

    /// Brings the open session to the front: the exact tab in iTerm and Terminal, otherwise the app that hosts it.
    @discardableResult
    static func focus(pid: Int32, tty: String?) -> Bool {
        if let tty, TerminalApp.iterm.installed, isRunning(.iterm), appleScript("""
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "none"
            """) == "ok" { return true }
        if let tty, isRunning(.terminal), appleScript("""
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            return "none"
            """) == "ok" { return true }
        // any other terminal: walk up from the claude process to the app that owns it and bring that app forward
        var p = pid
        for _ in 0..<12 {
            if let app = NSRunningApplication(processIdentifier: p), app.bundleIdentifier != nil {
                return app.activate()
            }
            guard let parent = parentPID(p), parent > 1 else { break }
            p = parent
        }
        return false
    }

    private static func isRunning(_ t: TerminalApp) -> Bool {
        t.bundleIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }

    private static func parentPID(_ pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func launch(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0] == "open" ? "/usr/bin/open" : args[0])
        p.arguments = Array(args.dropFirst())
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        try? p.run()
    }

    /// `tell application id` (not by name): an app that isn't installed must never make macOS ask "Where is …?".
    @discardableResult
    private static func appleScript(_ source: String) -> String? {
        var err: NSDictionary?
        let out = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err { NSLog("AppleScript failed: \(err)") }
        return out?.stringValue
    }
}
