import Foundation

struct Session: Identifiable, Hashable {
    let id: String
    let title: String
    let cwd: String
    let updated: Date
    let sizeMB: Double
    var openPID: Int32?
    var openTTY: String?

    var project: String { (cwd as NSString).lastPathComponent }
    var resumeCommand: String { "cd \(shellQuote(cwd)) && claude --resume \(id)" }
}

func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

/// Reads Claude Code's own files: ~/.claude/projects/*/<id>.jsonl (history) and ~/.claude/sessions/<pid>.json
/// (sessions running right now). Only sessions started from the terminal (entrypoint "cli") are listed, so
/// transcripts of SDK-driven agents (entrypoint "sdk-py") stay out.
@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var loading = false
    /// Session ids hidden from the main list. Only this list changes: Claude Code's files stay untouched.
    @Published var archived: Set<String> = SessionStore.loadArchived()

    /// The home folder to read Claude Code's files from. CLAUDE_SESSIONS_HOME points it elsewhere, so the app
    /// can be run against a folder of sample sessions (tests, screenshots) without touching the real ones.
    static let homeDir: URL = {
        if let p = ProcessInfo.processInfo.environment["CLAUDE_SESSIONS_HOME"], !p.isEmpty {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    private static var archiveFile: URL {
        homeDir.appendingPathComponent("Library/Application Support/ClaudeSessions/archived.json")
    }

    private static func loadArchived() -> Set<String> {
        guard let d = try? Data(contentsOf: archiveFile), let ids = try? JSONDecoder().decode([String].self, from: d)
        else { return [] }
        return Set(ids)
    }

    /// Titles the user gave sessions in this app (id -> title). Claude Code's own files stay untouched.
    @Published var titles: [String: String] = SessionStore.load("titles.json") ?? [:]

    func title(_ s: Session) -> String { titles[s.id] ?? s.title }

    func rename(_ s: Session, _ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        titles[s.id] = t.isEmpty || t == s.title ? nil : t
        Self.save(titles, "titles.json")
    }

    private static func load<T: Decodable>(_ name: String) -> T? {
        let f = archiveFile.deletingLastPathComponent().appendingPathComponent(name)
        guard let d = try? Data(contentsOf: f) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    private static func save<T: Encodable>(_ value: T, _ name: String) {
        let f = archiveFile.deletingLastPathComponent().appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: f)
    }

    func setArchived(_ s: Session, _ on: Bool) {
        if on { archived.insert(s.id) } else { archived.remove(s.id) }
        let f = Self.archiveFile
        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(archived.sorted()).write(to: f)
    }

    private let home = SessionStore.homeDir
    private var cache: [String: (mtime: Date, info: FileInfo?)] = [:]

    struct FileInfo { let title: String; let cwd: String }

    func refresh() {
        guard !loading else { return }       // the first scan of thousands of agent files takes a while
        loading = true
        let home = self.home
        let cache = self.cache
        Task.detached(priority: .userInitiated) {
            let (list, newCache) = Self.scan(home: home, cache: cache)
            await MainActor.run {
                self.cache = newCache
                self.sessions = list
                self.loading = false
            }
        }
    }

    nonisolated static func scan(home: URL, cache: [String: (mtime: Date, info: FileInfo?)])
        -> ([Session], [String: (mtime: Date, info: FileInfo?)]) {
        let fm = FileManager.default
        let projects = home.appendingPathComponent(".claude/projects")
        var files: [(URL, Date, Int)] = []
        for dir in (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
            where f.pathExtension == "jsonl" {
                let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                files.append((f, v?.contentModificationDate ?? .distantPast, v?.fileSize ?? 0))
            }
        }
        files.sort { $0.1 > $1.1 }
        let live = liveSessions(home: home)
        var out: [Session] = []
        var newCache: [String: (mtime: Date, info: FileInfo?)] = [:]
        for (url, mtime, size) in files {
            let key = url.path
            let info: FileInfo?
            if let c = cache[key], c.mtime == mtime { info = c.info } else { info = read(url) }
            newCache[key] = (mtime, info)
            guard let info else { continue }
            let id = url.deletingPathExtension().lastPathComponent
            out.append(Session(id: id, title: info.title, cwd: info.cwd, updated: mtime,
                               sizeMB: Double(size) / 1_000_000, openPID: live[id]?.pid, openTTY: live[id]?.tty))
            if out.count >= 150 { break }
        }
        return (out, newCache)
    }

    /// nil = not a terminal session (agent, or empty).
    nonisolated static func read(_ url: URL) -> FileInfo? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        // Fast path for the thousands of agent transcripts: their entrypoint shows up in the first few KB.
        if let peek = try? h.read(upToCount: 64 * 1024), let s = String(data: peek, encoding: .utf8) ?? String(data: peek.prefix(60_000), encoding: .ascii),
           s.contains("\"entrypoint\":\"sdk-") { return nil }
        try? h.seek(toOffset: 0)
        var cwd: String?, first: String?, entry: String?, headTitle: String?
        // File snapshots near the top can be hundreds of KB each, so read on in chunks until the fields are found.
        var buf = Data(), scanned = 0
        func lines() -> [Data] {
            guard let last = buf.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
            let complete = buf[buf.startIndex...last]
            buf = Data(buf[buf.index(after: last)...])
            return complete.split(separator: UInt8(ascii: "\n")).map { Data($0) }
        }
        outer: while scanned < 48 * 1024 * 1024, let chunk = try? h.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            scanned += chunk.count
            buf.append(chunk)
            for line in lines() where line.count < 200_000 {
                guard let r = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if headTitle == nil, let t = (r["customTitle"] as? String) ?? (r["aiTitle"] as? String) { headTitle = t }
                if entry == nil, let e = r["entrypoint"] as? String {
                    entry = e
                    if e != "cli" { return nil }
                }
                if cwd == nil, let c = r["cwd"] as? String { cwd = c }
                if first == nil, r["type"] as? String == "user", r["isMeta"] as? Bool != true,
                   let m = r["message"] as? [String: Any] {
                    var t = ""
                    if let s = m["content"] as? String { t = s }
                    else if let parts = m["content"] as? [[String: Any]] {
                        t = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: " ")
                    }
                    t = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty && !t.hasPrefix("<") { first = t.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
                }
                if entry != nil && cwd != nil && first != nil { break outer }
            }
        }
        guard entry == "cli", let cwd else { return nil }
        // Titles are appended as the session goes on: take the latest one from the end of the file.
        var title: String?
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 512 * 1024 ? size - 512 * 1024 : 0)
        let tail = (try? h.readToEnd()) ?? Data()
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            guard line.count < 4000, let s = String(data: Data(line), encoding: .utf8),
                  s.contains("title\"") else { continue }
            if let r = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
               let t = (r["customTitle"] as? String) ?? (r["aiTitle"] as? String) {
                title = t
                break
            }
        }
        let t = title ?? headTitle ?? first ?? "(bez opisu)"
        return FileInfo(title: String(t.prefix(160)), cwd: cwd)
    }

    /// sessionId -> running Claude Code process (from ~/.claude/sessions/<pid>.json, only live pids).
    nonisolated static func liveSessions(home: URL) -> [String: (pid: Int32, tty: String?)] {
        let dir = home.appendingPathComponent(".claude/sessions")
        var out: [String: (pid: Int32, tty: String?)] = [:]
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where f.pathExtension == "json" {
            guard let d = try? Data(contentsOf: f),
                  let r = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let sid = r["sessionId"] as? String, r["entrypoint"] as? String == "cli",
                  let pidN = r["pid"] as? Int, kill(pid_t(pidN), 0) == 0 else { continue }
            out[sid] = (pid_t(pidN), tty(of: pid_t(pidN)))
        }
        return out
    }

    nonisolated static func tty(of pid: pid_t) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "tty=", "-p", String(pid)]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty || s == "??" ? nil : "/dev/" + s
    }
}
