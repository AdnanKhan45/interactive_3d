import SceneKit

/// Validates whether a tap on a named entity is allowed based on
/// ordered selection rules.
///
/// When the user provides [SequenceConfig] entries, taps are constrained
/// so entities within a group can only be selected in the defined order.
/// Bidirectional configs allow selection in either direction from the
/// current position. Tied groups enforce matching indices across groups.
class SequenceValidator {

    struct Config {
        let group: String
        let order: [String]
        let bidirectional: Bool
        let tiedGroup: String?
    }

    private(set) var configs: [Config] = []
    private var allowedNext: [String: Set<String>] = [:]

    /// Parses sequence configs from the Flutter method call arguments.
    func configure(from array: [[String: Any]]) {
        configs = array.compactMap { dict in
            guard let group = dict["group"] as? String,
                  let order = dict["order"] as? [String],
                  let bidirectional = dict["bidirectional"] as? Bool else { return nil }
            return Config(
                group: group,
                order: order,
                bidirectional: bidirectional,
                tiedGroup: dict["tiedGroup"] as? String
            )
        }
        buildMaps()
    }

    /// Resets all sequence state.
    func reset() {
        configs.removeAll()
        allowedNext.removeAll()
    }

    /// Returns true if [nodeName] is allowed to be tapped given the current
    /// set of [selectedNodes].
    ///
    /// Rules:
    /// - Deselecting (tapping an already selected node) is always allowed.
    /// - Nodes not in any sequence are always allowed.
    /// - First pick in a group is free, unless a tied group has started
    ///   (then the matching index must be selected).
    /// - Subsequent picks must be adjacent via the forward (and optionally
    ///   backward) adjacency map.
    func isTapAllowed(_ nodeName: String, selectedNodes: Set<SCNNode>) -> Bool {
        // Deselecting is always allowed
        if selectedNodes.contains(where: { $0.name == nodeName }) {
            return true
        }

        guard let config = configs.first(where: { $0.order.contains(nodeName) }),
              let idx = config.order.firstIndex(of: nodeName) else {
            return true // not part of any sequence
        }

        let selectedInGroup = selectedNodes
            .compactMap { $0.name }
            .filter { config.order.contains($0) }

        var selectedInTied: [String] = []
        if let tiedName = config.tiedGroup,
           let tiedConfig = configs.first(where: { $0.group == tiedName }) {
            selectedInTied = selectedNodes
                .compactMap { $0.name }
                .filter { tiedConfig.order.contains($0) }
        }

        // Group hasn't started yet
        if selectedInGroup.isEmpty {
            if !selectedInTied.isEmpty,
               let tiedName = config.tiedGroup,
               let tiedConfig = configs.first(where: { $0.group == tiedName }) {
                let requiredNode = tiedConfig.order[idx]
                return selectedInTied.contains(requiredNode)
            }
            return true
        }

        // Once started, only adjacent nodes are allowed
        for name in selectedInGroup {
            if allowedNext[name]?.contains(nodeName) == true {
                return true
            }
        }

        return false
    }

    private func buildMaps() {
        allowedNext.removeAll()
        for config in configs {
            let list = config.order
            for (i, name) in list.enumerated() where i < list.count - 1 {
                let nextName = list[i + 1]
                allowedNext[name, default: []].insert(nextName)
                if config.bidirectional {
                    allowedNext[nextName, default: []].insert(name)
                }
            }
        }
    }
}
