import SceneKit

protocol NodeSink: AnyObject {
    func add(_ node: SCNNode)
}

extension SCNNode: NodeSink {
    func add(_ node: SCNNode) { addChildNode(node) }
}

final class StaticScene {
    final class Bag: NodeSink {
        fileprivate var nodes: [SCNNode] = []
        fileprivate var tags: [String: [SCNNode]] = [:]
        func add(_ node: SCNNode) { nodes.append(node) }
        func add(_ node: SCNNode, as tag: String) { nodes.append(node); tags[tag, default: []].append(node) }
    }

    private struct Piece { let key: String; let nodes: [SCNNode]; let tags: [String: [SCNNode]]; let drop: () -> Void }

    private let root = SCNNode()
    private var pieces: [String: Piece] = [:]
    private var seen: Set<String> = []
    private(set) var rebuilt: [String] = []
    private(set) var generation = 0

    init(under parent: SCNNode) { parent.addChildNode(root) }

    var nodes: [SCNNode] { root.childNodes }
    private var tagged: (generation: Int, nodes: [String: [SCNNode]])?
    func tagged(_ tag: String) -> [SCNNode] {
        if tagged?.generation != generation {
            var all: [String: [SCNNode]] = [:]
            for p in pieces.values { for (t, n) in p.tags { all[t, default: []] += n } }
            tagged = (generation, all)
        }
        return tagged?.nodes[tag] ?? []
    }
    func node(named name: String) -> SCNNode? { root.childNode(withName: name, recursively: true) }
    func enumerate(_ body: (SCNNode) -> Void) { root.enumerateHierarchy { n, _ in body(n) } }

    func pass(_ body: () -> Void) {
        seen = []
        rebuilt = []
        body()
        for (id, p) in pieces where !seen.contains(id) {
            p.nodes.forEach { $0.removeFromParentNode() }
            p.drop()
            pieces[id] = nil
            generation += 1
        }
    }

    func piece(_ id: String, key: String, drop: @escaping () -> Void = {}, _ build: (Bag) -> Void) {
        seen.insert(id)
        if let p = pieces[id], p.key == key { return }
        if let p = pieces[id] { p.nodes.forEach { $0.removeFromParentNode() }; p.drop() }
        let bag = Bag()
        build(bag)
        bag.nodes.forEach(root.addChildNode)
        pieces[id] = Piece(key: key, nodes: bag.nodes, tags: bag.tags, drop: drop)
        rebuilt.append(id)
        generation += 1
    }
}
