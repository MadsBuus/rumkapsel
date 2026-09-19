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
