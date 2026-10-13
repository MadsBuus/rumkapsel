import Foundation

enum BoardNumbers {
    private static let lock = NSLock()
    private static var repos: [Int: Set<String>] = [:]
    private static var onBoard: Set<String> = []

    static func note(_ items: [ProjectItem]) {
        var r: [Int: Set<String>] = [:]
        for it in items { r[it.number, default: []].insert(it.repo) }
        lock.lock(); repos = r; onBoard = Set(items.map(\.repo)); lock.unlock()
    }

    static func elsewhere(_ n: Int, than repo: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard onBoard.contains(repo), let held = repos[n] else { return false }
        return !held.contains(repo)
    }
}

struct Work: Hashable {
    var repo: String
    var branch: String?
    var issue: Int?
    var pull: Int?

    init(repo: String, branch: String? = nil, issue: Int? = nil, pull: Int? = nil) {
        self.repo = repo
        self.branch = branch
        self.issue = issue ?? branch.flatMap { Work.issue(inBranch: $0, repo: repo) }
        self.pull = pull
    }

    static let notWork: Set<String> = ["main", "master", "develop", "HEAD", ""]
    static let longLived: Set<String> = ["develop", "staging", "main", "master", "production"]

    static func issue(inBranch branch: String, repo: String) -> Int? {
        guard let n = branch.firstMatch(of: #/^gh-(\d+)\//#).flatMap({ Int($0.1) }) else { return nil }
        return BoardNumbers.elsewhere(n, than: repo) ? nil : n
    }

    static func guessedBranch(issue: Int) -> String { "gh-\(issue)" }

    var isTask: Bool { branch.map { !Work.notWork.contains($0) } ?? false || issue != nil || pull != nil }

    var number: Int? { issue ?? pull }

    var officeKey: String {
        if let n = number { return "task:\(repo)#\(n)" }
        if let branch, !Work.notWork.contains(branch) { return "task:\(repo)/\(branch)" }
        return "proj:\(repo)"
    }

    static func number(inOfficeKey key: String) -> Int? {
        guard key.hasPrefix("task:"), let hash = key.lastIndex(of: "#") else { return nil }
        return Int(key[key.index(after: hash)...])
    }

    var name: String {
        if let branch, let n = Work.issue(inBranch: branch, repo: repo), let slash = branch.firstIndex(of: "/") {
            let words = branch[branch.index(after: slash)...].split(separator: "-").joined(separator: " ")
            return "#\(n) " + Work.shorten(words, to: 22)
        }
        if let branch, !Work.notWork.contains(branch) {
            let slug = branch.split(separator: "/").last.map(String.init) ?? branch
            return Work.shorten(slug.replacingOccurrences(of: "-", with: " "), to: 26)
        }
        return repo
    }

    var label: String { number.map { "#\($0)" } ?? branch ?? repo }

    var home: Home { Home(key: officeKey, name: name, repo: repo, issue: number) }

    static func shorten(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let words = text.split(separator: " ")
        var out = ""
        for w in words {
            if out.isEmpty { out = String(w); continue }
            if out.count + 1 + w.count > limit { break }
            out += " " + w
        }
        return String(out.prefix(limit))
    }
}

final class WorkBook {
    final class Record {
        let id: Int
        let repo: String
        var branches: Set<String> = []
        var folders: Set<String> = []
        var issue: Int?
        var pulls: [Int: String] = [:]
        var crate: Int?
        var author: String?
        var title: String?
        var url: String?

        var stage: Stage?
        var stagedAt: Date?
        var stagedBy: Source?
        var quiet = false
        var words: [Source: Stage] = [:]

        init(id: Int, repo: String) { self.id = id; self.repo = repo }

        var branchIssue: Int? { branches.lazy.compactMap { Work.issue(inBranch: $0, repo: self.repo) }.min() }
        func work(branch preferred: String? = nil) -> Work {
            let branch = preferred.flatMap { branches.contains($0) ? $0 : nil } ?? branches.sorted().first
            let open = pulls.filter { $0.value == "OPEN" }.keys.min()
            return Work(repo: repo, branch: branch, issue: branchIssue, pull: open ?? pulls.keys.max())
        }
        var number: Int? { issue ?? branchIssue ?? pulls.keys.min() ?? crate }
        var officeKeys: [String] {
            var keys = [work().officeKey]
            for b in branches.sorted() { keys.append(Work(repo: repo, branch: b).officeKey) }
            if let n = number { keys.append(Work(repo: repo, issue: n).officeKey) }
            return keys.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
    }

    private var records: [Int: Record] = [:]
    private var byBranch: [String: Int] = [:]
    private var byFolder: [String: Int] = [:]
    private var byIssue: [String: Int] = [:]
    private var byPull: [String: Int] = [:]
    private var byCrate: [String: Int] = [:]
    private var nextId = 1

    var onTransition: ((Record, Transition) -> Void)?

    func find(repo: String, branch: String) -> Record? { byBranch["\(repo)|\(branch)"].flatMap { records[$0] } }
    func find(folder: String) -> Record? { byFolder[folder].flatMap { records[$0] } }
    func find(repo: String, issue: Int) -> Record? { byIssue["\(repo)#\(issue)"].flatMap { records[$0] } }
    func find(repo: String, pull: Int) -> Record? { byPull["\(repo)!\(pull)"].flatMap { records[$0] } }
    func find(repo: String, crate n: Int) -> Record? {
        find(repo: repo, issue: n) ?? find(repo: repo, pull: n) ?? byCrate["\(repo)|\(n)"].flatMap { records[$0] }
    }
    func note(repo: String, crate n: Int) -> Record {
        if let r = find(repo: repo, crate: n) { return r }
        let record = Record(id: nextId, repo: repo); nextId += 1
        record.crate = n
        records[record.id] = record
        byCrate["\(repo)|\(n)"] = record.id
        return record
    }

    var workflow: (String) -> Workflow = { _ in Workflow() }

    func report(_ record: Record, _ stage: Stage, by source: Source, at: Date) {
        if let t = record.hear(Signal(stage: stage, by: source, at: at), workflow: workflow(record.repo)) { onTransition?(record, t) }
    }

    func find(officeKey key: String, repo: String) -> Record? {
        if let n = Work.number(inOfficeKey: key) { return find(repo: repo, issue: n) ?? find(repo: repo, pull: n) }
        guard key.hasPrefix("task:\(repo)/") else { return nil }
        return find(repo: repo, branch: String(key.dropFirst("task:\(repo)/".count)))
    }

    @discardableResult
    func note(repo: String, branch: String? = nil, folder: String? = nil, issue: Int? = nil, pull: Int? = nil, pullState: String? = nil,
              author: String? = nil, title: String? = nil, url: String? = nil) -> Record {
        var found: [Record] = []
        if let branch, !Work.notWork.contains(branch) {
            if let r = find(repo: repo, branch: branch) { found.append(r) }
            if let n = Work.issue(inBranch: branch, repo: repo), let r = find(repo: repo, issue: n) { found.append(r) }
        }
        if let folder, let r = find(folder: folder) {
            let named = branch.flatMap { Work.notWork.contains($0) ? nil : $0 }
            if named == nil || r.branches.isEmpty || r.branches.contains(named!) { found.append(r) }
        }
        if let issue, let r = find(repo: repo, issue: issue) { found.append(r) }
        if let pull, let r = find(repo: repo, pull: pull) { found.append(r) }
        for n in [issue, pull].compactMap({ $0 }) { if let r = byCrate["\(repo)|\(n)"].flatMap({ records[$0] }) { found.append(r) } }
        let record: Record
        if let first = found.min(by: { $0.id < $1.id }) {
            record = first
            for other in found where other.id != record.id { merge(other, into: record) }
        } else {
            record = Record(id: nextId, repo: repo); nextId += 1
            records[record.id] = record
        }
        if let branch, !Work.notWork.contains(branch) { record.branches.insert(branch); byBranch["\(repo)|\(branch)"] = record.id }
        if let folder { record.folders.insert(folder); byFolder[folder] = record.id }
        if let issue { record.issue = record.issue ?? issue; byIssue["\(repo)#\(issue)"] = record.id }
        if let n = record.branchIssue { byIssue["\(repo)#\(n)"] = record.id }
        if let pull { record.pulls[pull] = pullState ?? record.pulls[pull] ?? "OPEN"; byPull["\(repo)!\(pull)"] = record.id }
        if let author, !author.isEmpty, author != "?" { record.author = author }
        if let title, !title.isEmpty { record.title = title }
        if let url, !url.isEmpty { record.url = url }
        return record
    }

    private func merge(_ other: Record, into record: Record) {
        for b in other.branches { record.branches.insert(b); byBranch["\(record.repo)|\(b)"] = record.id }
        for f in other.folders { record.folders.insert(f); byFolder[f] = record.id }
        if let i = other.issue { record.issue = record.issue ?? i; byIssue["\(record.repo)#\(i)"] = record.id }
        if let n = other.branchIssue { byIssue["\(record.repo)#\(n)"] = record.id }
        for (n, s) in other.pulls { record.pulls[n] = record.pulls[n] ?? s; byPull["\(record.repo)!\(n)"] = record.id }
        if let n = other.crate { record.crate = record.crate ?? n; byCrate["\(record.repo)|\(n)"] = record.id }
        record.author = record.author ?? other.author; record.title = record.title ?? other.title; record.url = record.url ?? other.url
        if let s = other.stage, record.stage.map({ s > $0 }) ?? true { record.stage = s; record.stagedAt = other.stagedAt; record.stagedBy = other.stagedBy }
        for (src, st) in other.words where record.words[src].map({ st > $0 }) ?? true { record.words[src] = st }
        records[other.id] = nil
    }

    var count: Int { records.count }
    func records(repo: String) -> [Record] { records.values.filter { $0.repo == repo }.sorted { $0.id < $1.id } }
}
