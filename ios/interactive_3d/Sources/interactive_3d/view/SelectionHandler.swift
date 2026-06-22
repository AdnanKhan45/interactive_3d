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

    /// Accumulated PBR override params per geometry node. Merged across calls;
    /// cleared by resetMaterialOverride.
    var overrideParams: [SCNNode: [String: Any]] = [:]

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

    /// Restores [node] to the override material if one exists, otherwise to the
    /// GLB original. Drops [originalMaterials] only when no override remains.
    func resetNodeColor(_ node: SCNNode) {
        guard let geometry = node.geometry else { return }
        guard let original = originalMaterials[node] else { return }

        let restoreTo: SCNMaterial = computeOverrideMaterial(for: node) ?? (original.copy() as! SCNMaterial)
        geometry.materials = [restoreTo]

        if overrideParams[node] == nil {
            originalMaterials.removeValue(forKey: node)
        }
    }

    /// Merges [params] into this node's accumulated override and applies
    /// the result if the node is not currently selected.
    func applyMaterialOverride(to node: SCNNode, params: [String: Any]) {
        guard let geometry = node.geometry, let material = geometry.firstMaterial else { return }
        if originalMaterials[node] == nil {
            originalMaterials[node] = material.copy() as? SCNMaterial
        }

        var merged = overrideParams[node] ?? [:]
        for (k, v) in params { merged[k] = v }
        overrideParams[node] = merged

        // Selection takes precedence visually; we just stored the deselect target.
        let parent = findNamedParent(of: node)
        if let p = parent, selectedNodes.contains(p) { return }

        if let overrideMat = computeOverrideMaterial(for: node) {
            geometry.materials = [overrideMat]
        }
    }

    /// Removes the override on [node] and restores the GLB original if visible.
    func resetMaterialOverride(_ node: SCNNode) {
        overrideParams.removeValue(forKey: node)
        guard let geometry = node.geometry, let original = originalMaterials[node] else { return }

        let parent = findNamedParent(of: node)
        if let p = parent, selectedNodes.contains(p) { return }

        geometry.materials = [original.copy() as! SCNMaterial]
        originalMaterials.removeValue(forKey: node)
    }

    /// Decodes [data] into a base color texture and merges it into [node]'s
    /// override. Stored as a UIImage so recompute does not re-decode.
    func applyEntityTexture(to node: SCNNode, data: Data) {
        guard let image = UIImage(data: data) else { return }
        applyMaterialOverride(to: node, params: ["textureImage": Self.downsampled(image)])
    }

    /// Caps a texture at maxTextureDim on its longest side to bound GPU memory.
    /// SceneKit documents no maximum, so we match the Android policy.
    private static let maxTextureDim: CGFloat = 2048

    private static func downsampled(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let pxW = CGFloat(cg.width), pxH = CGFloat(cg.height)
        let longest = max(pxW, pxH)
        guard longest > maxTextureDim else { return image }
        let scale = maxTextureDim / longest
        let size = CGSize(width: pxW * scale, height: pxH * scale)
        print("interactive_3d: texture \(Int(pxW))x\(Int(pxH)) exceeds \(Int(maxTextureDim))px, downsampling to \(Int(size.width))x\(Int(size.height))")
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Removes the texture on [node], keeping any color/PBR override. Falls back
    /// to a full override reset when nothing else remains.
    func resetEntityTexture(_ node: SCNNode) {
        guard var params = overrideParams[node], params["textureImage"] != nil else { return }
        params.removeValue(forKey: "textureImage")
        if params.isEmpty {
            resetMaterialOverride(node)
            return
        }
        overrideParams[node] = params

        let parent = findNamedParent(of: node)
        if let p = parent, selectedNodes.contains(p) { return }
        if let geometry = node.geometry, let overrideMat = computeOverrideMaterial(for: node) {
            geometry.materials = [overrideMat]
        }
    }

    /// Builds the override material for [node] from a fresh copy of its original,
    /// applying every accumulated param. Returns nil if no override is registered.
    private func computeOverrideMaterial(for node: SCNNode) -> SCNMaterial? {
        guard let params = overrideParams[node], let original = originalMaterials[node] else { return nil }
        let m = original.copy() as! SCNMaterial

        if let img = params["textureImage"] as? UIImage {
            m.diffuse.contents = img
            m.diffuse.mipFilter = .linear
        }
        if let c = params["color"] as? [Double], c.count == 4 {
            m.multiply.contents = UIColor(
                red: CGFloat(c[0]), green: CGFloat(c[1]),
                blue: CGFloat(c[2]), alpha: CGFloat(c[3])
            )
        }
        if let metallic = params["metallic"] as? Double {
            m.metalness.contents = NSNumber(value: metallic)
        }
        if let roughness = params["roughness"] as? Double {
            m.roughness.contents = NSNumber(value: roughness)
        }
        if let e = params["emissive"] as? [Double], e.count == 3 {
            m.emission.contents = UIColor(
                red: CGFloat(e[0]), green: CGFloat(e[1]),
                blue: CGFloat(e[2]), alpha: 1.0
            )
        }
        return m
    }

    /// Walks up from a geometry node to find the named parent that
    /// selectedNodes tracks.
    private func findNamedParent(of node: SCNNode) -> SCNNode? {
        var n: SCNNode? = node
        while n != nil {
            if let name = n!.name,
               !name.isEmpty,
               !name.starts(with: "Mesh."),
               !name.hasSuffix(".001") {
                return n
            }
            n = n?.parent
        }
        return nil
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
    /// Overridden entities are skipped; override wins visually over cache.
    func highlightCachedEntities(in scene: SCNScene) {
        guard enableCache, let cacheMgr = cacheManager else { return }
        for cachedName in cacheMgr.cachedEntities {
            scene.rootNode.enumerateChildNodes { (node, _) in
                if let nodeName = node.name, nodeName == cachedName,
                   let geometryNode = self.findGeometryNode(in: node),
                   self.overrideParams[geometryNode] == nil {
                    self.applyCacheHighlight(to: geometryNode)
                }
            }
        }
    }

    /// Resets everything, then re-applies cache and selection in priority order.
    /// Priority on refresh: selection > override > cache > GLB original.
    func refreshAllHighlights(in scene: SCNScene) {
        // 1. Reset all nodes. resetNodeColor restores override-or-original.
        scene.rootNode.enumerateChildNodes { (node, _) in
            if let geometryNode = self.findGeometryNode(in: node) {
                self.resetNodeColor(geometryNode)
            }
        }
        // 2. Cache highlights, skipping any entity that has an override.
        var cachedSet = Set<String>()
        if enableCache, let cacheMgr = cacheManager {
            for cachedName in cacheMgr.cachedEntities {
                cachedSet.insert(cachedName)
                scene.rootNode.enumerateChildNodes { (node, _) in
                    if let nodeName = node.name, nodeName == cachedName,
                       let geometryNode = self.findGeometryNode(in: node),
                       self.overrideParams[geometryNode] == nil {
                        self.applyCacheHighlight(to: geometryNode)
                    }
                }
            }
        }
        // 3. Selection on top (regardless of cache or override status).
        for node in selectedNodes {
            if let name = node.name, !cachedSet.contains(name),
               let geometryNode = findGeometryNode(in: node) {
                applyHighlight(to: geometryNode, forNodeName: name)
            }
        }
        // 4. Clear selections if configured.
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

    /// Resets all selection and override state. Call before loading a new model.
    func reset() {
        selectedNodes.removeAll()
        originalMaterials.removeAll()
        overrideParams.removeAll()
    }

    /// Full cleanup — releases all references.
    func cleanup() {
        reset()
        patchColors = nil
        selectionColor = nil
        cacheManager = nil
    }
}
