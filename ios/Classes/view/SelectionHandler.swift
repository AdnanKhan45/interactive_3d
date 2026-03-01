import SceneKit
import UIKit

/// Handles entity selection, highlighting, and cache coloring for SceneKit.
///
/// Manages original material backup/restore, per-entity color resolution
/// (patch colors vs global selection color), and cache highlight application.
class SelectionHandler {

    var selectedNodes: Set<SCNNode> = []
    var originalMaterials: [SCNNode: SCNMaterial] = [:]
    var selectionColor: [Double]?
    var patchColors: [[String: Any]]?
    var clearSelectionsOnHighlight: Bool = false

    // Cache
    var enableCache: Bool = false
    var cacheManager: Interactive3DCacheManager?
    var cacheColor: UIColor = UIColor(red: 0.8, green: 0.8, blue: 0.2, alpha: 0.6)

    /// Finds the first descendant (or self) that has geometry attached.
    func findGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = findGeometryNode(in: child) { return found }
        }
        return nil
    }

    /// Resolves the highlight color for a named entity.
    /// Checks patch colors first, then falls back to the global selection color,
    /// then to default red.
    func resolveColor(for nodeName: String?) -> UIColor {
        if let nodeName = nodeName, let patchColors = patchColors {
            for patch in patchColors {
                if let name = patch["name"] as? String, name == nodeName,
                   let color = patch["color"] as? [Double], color.count == 4 {
                    return UIColor(
                        red: CGFloat(color[0]),
                        green: CGFloat(color[1]),
                        blue: CGFloat(color[2]),
                        alpha: CGFloat(color[3])
                    )
                }
            }
        }
        if let color = selectionColor, color.count == 4 {
            return UIColor(
                red: CGFloat(color[0]),
                green: CGFloat(color[1]),
                blue: CGFloat(color[2]),
                alpha: CGFloat(color[3])
            )
        }
        return UIColor.red
    }

    /// Applies the selection highlight color to a geometry node.
    /// Backs up the original material on first highlight.
    func applyHighlight(to node: SCNNode, forNodeName nodeName: String?) {
        guard let geometry = node.geometry, let material = geometry.firstMaterial else { return }
        if originalMaterials[node] == nil {
            originalMaterials[node] = material.copy() as? SCNMaterial
        }
        let color = resolveColor(for: nodeName)
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.3)
        material.multiply.contents = color
    }

    /// Applies cache highlight color to a geometry node.
    /// Backs up the original material on first highlight.
    func applyCacheHighlight(to node: SCNNode) {
        guard let geometry = node.geometry, let material = geometry.firstMaterial else { return }
        if originalMaterials[node] == nil {
            originalMaterials[node] = material.copy() as? SCNMaterial
        }
        material.diffuse.contents = cacheColor
        material.emission.contents = cacheColor.withAlphaComponent(0.2)
        material.multiply.contents = cacheColor
    }

    /// Restores the original material on a geometry node.
    /// Uses a copy to break pointer sharing, then removes the backup.
    func resetNodeColor(_ node: SCNNode) {
        guard let geometry = node.geometry else { return }
        if let originalMaterial = originalMaterials[node] {
            geometry.materials = [originalMaterial.copy() as! SCNMaterial]
            originalMaterials.removeValue(forKey: node)
        }
    }

    /// Unselects entities by hash ID, or all if [entityIds] is nil.
    func unselectEntities(entityIds: [Int]?) {
        if let ids = entityIds {
            let nodesToRemove = selectedNodes.filter { ids.contains($0.hash) }
            for node in nodesToRemove {
                if let geometryNode = findGeometryNode(in: node) {
                    resetNodeColor(geometryNode)
                    selectedNodes.remove(node)
                }
            }
        } else {
            for node in selectedNodes {
                if let geometryNode = findGeometryNode(in: node) {
                    resetNodeColor(geometryNode)
                }
            }
            selectedNodes.removeAll()
        }
    }

    /// Highlights all entities that are in the persistent cache.
    func highlightCachedEntities(in scene: SCNScene) {
        guard enableCache, let cacheMgr = cacheManager else { return }
        for cachedName in cacheMgr.cachedEntities {
            scene.rootNode.enumerateChildNodes { (node, _) in
                if let nodeName = node.name, nodeName == cachedName,
                   let geometryNode = self.findGeometryNode(in: node) {
                    self.applyCacheHighlight(to: geometryNode)
                }
            }
        }
    }

    /// Refreshes all highlights: resets everything, then re-applies cache
    /// and selection colors in the correct priority order.
    func refreshAllHighlights(in scene: SCNScene) {
        // 1. Reset all nodes
        scene.rootNode.enumerateChildNodes { (node, _) in
            if let geometryNode = self.findGeometryNode(in: node) {
                self.resetNodeColor(geometryNode)
            }
        }
        // 2. Cache highlights (takes priority)
        var cachedSet = Set<String>()
        if enableCache, let cacheMgr = cacheManager {
            for cachedName in cacheMgr.cachedEntities {
                cachedSet.insert(cachedName)
                scene.rootNode.enumerateChildNodes { (node, _) in
                    if let nodeName = node.name, nodeName == cachedName,
                       let geometryNode = self.findGeometryNode(in: node) {
                        self.applyCacheHighlight(to: geometryNode)
                    }
                }
            }
        }
        // 3. Selection highlights (only for non-cached nodes)
        for node in selectedNodes {
            if let name = node.name, !cachedSet.contains(name),
               let geometryNode = findGeometryNode(in: node) {
                applyHighlight(to: geometryNode, forNodeName: name)
            }
        }
        // 4. Clear selections if configured
        if clearSelectionsOnHighlight {
            selectedNodes.removeAll()
        }
    }

    /// Clears the persistent cache and restores cached entity materials.
    /// Re-applies selection color for entities that are still actively selected.
    func clearCache(in scene: SCNScene) {
        guard enableCache, let cacheMgr = cacheManager else { return }
        let entitiesToClear = Array(cacheMgr.cachedEntities)
        cacheMgr.clearCache()

        scene.rootNode.enumerateChildNodes { (node, _) in
            if let nodeName = node.name, entitiesToClear.contains(nodeName),
               let geometryNode = self.findGeometryNode(in: node) {
                self.resetNodeColor(geometryNode)
                // Re-apply selection color if entity is still selected
                if self.selectedNodes.contains(node) {
                    self.applyHighlight(to: geometryNode, forNodeName: nodeName)
                }
            }
        }
    }

    /// Removes specific entities from the cache by name.
    func removeFromCache(names: [String], in scene: SCNScene) {
        let cacheMgr = enableCache ? cacheManager : nil
        for name in names {
            cacheMgr?.removeFromCache(name)
            if let node = scene.rootNode.childNode(withName: name, recursively: true) {
                selectedNodes.remove(node)
                if let geometryNode = findGeometryNode(in: node) {
                    resetNodeColor(geometryNode)
                }
            } else {
                scene.rootNode.enumerateChildNodes { (node, stop) in
                    if let nodeName = node.name, nodeName == name {
                        self.selectedNodes.remove(node)
                        if let geometryNode = self.findGeometryNode(in: node) {
                            self.resetNodeColor(geometryNode)
                        }
                        stop.pointee = true
                    }
                }
            }
        }
    }

    /// Resets all selection state. Call before loading a new model.
    func reset() {
        selectedNodes.removeAll()
        originalMaterials.removeAll()
    }

    /// Full cleanup — releases all references.
    func cleanup() {
        reset()
        patchColors = nil
        selectionColor = nil
        cacheManager = nil
    }
}
