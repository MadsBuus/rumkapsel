import Foundation

/// One piece of work: a branch, and the pull request and issue it comes to have. The one place that
/// says what a piece of work is called: its office key, its crate number, its name on the floor. Every
/// source that names work, a session's branch, a teammate's pull request, a board issue, the merge
/// history, goes through here, so that the same work is one office and one crate wherever it was heard of.
///
/// Today the names are what they always were: the office is keyed by the issue where one is known,
/// else the pull request, else the branch; the crate is numbered by the issue, else the pull request.
/// STAGES.md says where that is going; this is the one place it will change.
struct Work: Hashable {
    var repo: String
    var branch: String?
    var issue: Int?
    var pull: Int?

    init(repo: String, branch: String? = nil, issue: Int? = nil, pull: Int? = nil) {
        self.repo = repo
        self.branch = branch
        self.issue = issue ?? branch.flatMap(Work.issue(inBranch:))
        self.pull = pull
    }

    /// Branches that are not a piece of work but the trunk itself, or no branch at all.
    static let notWork: Set<String> = ["main", "master", "develop", "HEAD", ""]
    /// The long-lived branches a pipeline is made of: a pull request from one of these is a release, not work.
    static let longLived: Set<String> = ["develop", "staging", "main", "master", "production"]

    /// A branch named for its issue: `gh-128/anything` is issue 128.
    static func issue(inBranch branch: String) -> Int? {
        branch.firstMatch(of: #/^gh-(\d+)\//#).flatMap { Int($0.1) }
    }

    /// A branch name to stand in for one not known yet, from the issue the board says the work is for.
    static func guessedBranch(issue: Int) -> String { "gh-\(issue)" }

    /// Whether this is a piece of work at all, or a session sat on the trunk.
    var isTask: Bool { branch.map { !Work.notWork.contains($0) } ?? false || issue != nil || pull != nil }

    /// The number the work goes by: its issue, else its pull request.
    var number: Int? { issue ?? pull }

    /// The office's key: `task:repo#N` by number, `task:repo/branch` by branch, `proj:repo` for the trunk.
    var officeKey: String {
        if let n = number { return "task:\(repo)#\(n)" }
        if let branch, !Work.notWork.contains(branch) { return "task:\(repo)/\(branch)" }
        return "proj:\(repo)"
    }

    /// The number in an office key, where the key carries one: `task:repo#128`.
    static func number(inOfficeKey key: String) -> Int? {
        guard key.hasPrefix("task:"), let hash = key.lastIndex(of: "#") else { return nil }
        return Int(key[key.index(after: hash)...])
    }

    /// The office's name on the floor: the issue and the branch's words, or the branch's last part.
    var name: String {
        if let branch, let n = Work.issue(inBranch: branch), let slash = branch.firstIndex(of: "/") {
            let words = branch[branch.index(after: slash)...].split(separator: "-").joined(separator: " ")
            return "#\(n) " + Work.shorten(words, to: 22)
        }
        if let branch, !Work.notWork.contains(branch) {
            let slug = branch.split(separator: "/").last.map(String.init) ?? branch
            return Work.shorten(slug.replacingOccurrences(of: "-", with: " "), to: 26)
        }
        return repo
    }

    /// The short way to say which work: `#128`, or the branch.
    var label: String { number.map { "#\($0)" } ?? branch ?? repo }

    var home: Home { Home(key: officeKey, name: name, repo: repo, issue: number) }

    /// Cuts at a word boundary near the limit, without a trailing ellipsis noise.
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

/// Every piece of work the station has heard of, by every name it goes by. A record is made the first
/// time work is seen, from whatever saw it: a checkout folder, a branch, a pull request or a board issue,
/// and each source that comes after adds the names it knows. Two records that turn out to share a name are
/// one piece of work, and become one record. The floor asks here, never a source, for what work a name means.
final class WorkBook {
    final class Record {
        let id: Int
        let repo: String
        var branches: Set<String> = []
        var folders: Set<String> = []
        /// The issue the work is for, as a pull request's `closes #N` or the board said.
        var issue: Int?
        /// Pull requests by number, with the state each was last heard in.
        var pulls: [Int: String] = [:]
        /// A crate number heard from the counts, issue or pull request unknown which, when nothing else names the work yet.
        var crate: Int?

        /// Where the work is, who last moved it there and when, and each source's last word.
        var stage: Stage?
        var stagedAt: Date?
        var stagedBy: Source?
        var words: [Source: Stage] = [:]

        init(id: Int, repo: String) { self.id = id; self.repo = repo }

        /// The issue a branch is named for, `gh-N/…`: the one name that is on the office from the start.
        var branchIssue: Int? { branches.lazy.compactMap(Work.issue(inBranch:)).min() }
        /// The work as the floor names it now: the branch's issue, else the open pull request, else the
        /// branch. A pull request that closed or merged no longer names the office; the branch does again,
        /// as it always has, so a session lingering on a merged branch is where it was. The branch asked
        /// for is used when the record has several, so a session is named by the one it is on.
        func work(branch preferred: String? = nil) -> Work {
            let branch = preferred.flatMap { branches.contains($0) ? $0 : nil } ?? branches.sorted().first
            let open = pulls.filter { $0.value == "OPEN" }.keys.min()
            return Work(repo: repo, branch: branch, issue: branchIssue, pull: open)
        }
        /// The crate's number: the issue the work is for, else the branch's, else its pull request.
        var number: Int? { issue ?? branchIssue ?? pulls.keys.min() ?? crate }
        /// Every key an office for this work might stand under today: by number, or by any of its
        /// branches, since a teammate's office is keyed by branch while yours is re-keyed by its pull request.
        var officeKeys: [String] {
            var keys = [work().officeKey]
            for b in branches.sorted() { keys.append(Work(repo: repo, branch: b).officeKey) }
            if let n = number { keys.append(Work(repo: repo, issue: n).officeKey) }
            return keys.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
    }

    private var records: [Int: Record] = [:]
    private var byBranch: [String: Int] = [:]   // "repo|branch"
    private var byFolder: [String: Int] = [:]
    private var byIssue: [String: Int] = [:]    // "repo#N"
    private var byPull: [String: Int] = [:]     // "repo!N"
    private var byCrate: [String: Int] = [:]    // "repo|N", a number of unknown kind
    private var nextId = 1

    /// What the trace hears of every stage change.
    var onTransition: ((Record, Transition) -> Void)?

    func find(repo: String, branch: String) -> Record? { byBranch["\(repo)|\(branch)"].flatMap { records[$0] } }
    func find(folder: String) -> Record? { byFolder[folder].flatMap { records[$0] } }
    func find(repo: String, issue: Int) -> Record? { byIssue["\(repo)#\(issue)"].flatMap { records[$0] } }
    func find(repo: String, pull: Int) -> Record? { byPull["\(repo)!\(pull)"].flatMap { records[$0] } }
    /// The record a crate number means: the issue, the pull request, or a number only the counts have said.
    func find(repo: String, crate n: Int) -> Record? {
        find(repo: repo, issue: n) ?? find(repo: repo, pull: n) ?? byCrate["\(repo)|\(n)"].flatMap { records[$0] }
    }
    /// A crate number from the counts, noted as work in its own right when nothing else has named it.
    func note(repo: String, crate n: Int) -> Record {
        if let r = find(repo: repo, crate: n) { return r }
        let record = Record(id: nextId, repo: repo); nextId += 1
        record.crate = n
        records[record.id] = record
        byCrate["\(repo)|\(n)"] = record.id
        return record
    }

    /// The workflow of a repository, asked when a word is heard; every stage, every source, until set.
    var workflow: (String) -> Workflow = { _ in Workflow() }

    /// A source's word about a piece of work, by the rules in `Stage`; the trace hears any change.
    func report(_ record: Record, _ stage: Stage, by source: Source, at: Date = Date()) {
        if let t = record.hear(Signal(stage: stage, by: source, at: at), workflow: workflow(record.repo)) { onTransition?(record, t) }
    }

    /// The record behind an office key as the floor writes it today, `task:repo#N` or `task:repo/branch`.
    func find(officeKey key: String, repo: String) -> Record? {
        if let n = Work.number(inOfficeKey: key) { return find(repo: repo, issue: n) ?? find(repo: repo, pull: n) }
        guard key.hasPrefix("task:\(repo)/") else { return nil }
        return find(repo: repo, branch: String(key.dropFirst("task:\(repo)/".count)))
    }

    /// Writes down what a source knows about one piece of work, and answers with its record. Any name
    /// that is already someone's finds that record; the rest are added to it. Names that belong to two
    /// records fold them into one, the older keeping its id.
    @discardableResult
    func note(repo: String, branch: String? = nil, folder: String? = nil, issue: Int? = nil, pull: Int? = nil, pullState: String? = nil) -> Record {
        var found: [Record] = []
        if let branch, !Work.notWork.contains(branch) {
            if let r = find(repo: repo, branch: branch) { found.append(r) }
            if let n = Work.issue(inBranch: branch), let r = find(repo: repo, issue: n) { found.append(r) }
        }
        if let folder, let r = find(folder: folder) { found.append(r) }
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
        return record
    }

    private func merge(_ other: Record, into record: Record) {
        for b in other.branches { record.branches.insert(b); byBranch["\(record.repo)|\(b)"] = record.id }
        for f in other.folders { record.folders.insert(f); byFolder[f] = record.id }
        if let i = other.issue { record.issue = record.issue ?? i; byIssue["\(record.repo)#\(i)"] = record.id }
        if let n = other.branchIssue { byIssue["\(record.repo)#\(n)"] = record.id }
        for (n, s) in other.pulls { record.pulls[n] = record.pulls[n] ?? s; byPull["\(record.repo)!\(n)"] = record.id }
        if let n = other.crate { record.crate = record.crate ?? n; byCrate["\(record.repo)|\(n)"] = record.id }
        // The stage goes with the record that is furthest along; each source's word is kept where newer.
        if let s = other.stage, record.stage.map({ s > $0 }) ?? true { record.stage = s; record.stagedAt = other.stagedAt; record.stagedBy = other.stagedBy }
        for (src, st) in other.words where record.words[src].map({ st > $0 }) ?? true { record.words[src] = st }
        records[other.id] = nil
    }

    var count: Int { records.count }
    /// Every piece of work of a repository, by id.
    func records(repo: String) -> [Record] { records.values.filter { $0.repo == repo }.sorted { $0.id < $1.id } }
}
