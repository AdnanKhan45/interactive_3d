import SceneKit
import GLTFSceneKit
import UIKit

/// Loads 3D models into a SceneKit scene and manages scene lifecycle.
///
/// Handles two loading paths: SCNSceneSource (native) with GLTFSceneSource
/// as fallback. Applies default lighting when the model doesn't include
/// light nodes, and supports HDR/EXR background image loading.
class SceneManager {

    private weak var scnView: SCNView?
    var cameraNode: SCNNode?
    var useSolidBackground = false

    /// Node opacity tracking for part group visibility.
    var nodeOpacities: [SCNNode: CGFloat] = [:]

    init(scnView: SCNView) {
        self.scnView = scnView
    }

    /// Removes all nodes, geometry, materials, and textures from the current
    /// scene to prevent memory accumulation across model loads.
    func cleanupPreviousModel() {
        nodeOpacities.removeAll()

        if let scene = scnView?.scene {
            scene.rootNode.enumerateChildNodes { (node, _) in
                if let geometry = node.geometry {
                    for material in geometry.materials {
                        material.diffuse.contents = nil
                        material.normal.contents = nil
                        material.emission.contents = nil
                        material.multiply.contents = nil
                        material.specular.contents = nil
                        material.roughness.contents = nil
                        material.metalness.contents = nil
                        material.ambientOcclusion.contents = nil
                    }
                    geometry.materials = []
                    node.geometry = nil
                }
                node.removeFromParentNode()
            }
            scene.background.contents = nil
            scene.lightingEnvironment.contents = nil
        }

        SCNTransaction.flush()
        cameraNode = nil
        homePose = nil
    }

    /// Loads a GLB/glTF model from raw bytes into the scene view.
    ///
    /// Tries SCNSceneSource first (faster for simple models), falls back to
    /// GLTFSceneSource for full glTF 2.0 support. [resources] holds a .gltf's
    /// external files keyed by path relative to the model.
    func loadModel(modelBytes: Data, name: String, resources: [String: Data]) throws {
        cleanupPreviousModel()

        let scene: SCNScene
        do {
            let sceneSource = SCNSceneSource(data: modelBytes, options: [
                SCNSceneSource.LoadingOption.createNormalsIfAbsent: true,
                SCNSceneSource.LoadingOption.checkConsistency: true
            ])
            guard let loadedScene = sceneSource?.scene(options: nil) else {
                throw NSError(domain: "SceneManager", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "SCNSceneSource failed"])
            }
            scene = loadedScene
        } catch {
            scene = try loadWithGLTFSceneKit(modelBytes: modelBytes, name: name, resources: resources)
        }

        // Apply fallback materials to nodes without diffuse content
        scene.rootNode.enumerateChildNodes { (node, _) in
            if let geometry = node.geometry {
                if geometry.materials.isEmpty || geometry.firstMaterial?.diffuse.contents == nil {
                    let fallback = SCNMaterial()
                    fallback.diffuse.contents = UIColor.green
                    fallback.isDoubleSided = true
                    geometry.materials = [fallback]
                }
            }
        }

        // Add default lighting if model has none
        if !hasLightNodes(in: scene.rootNode) {
            addDefaultLighting(to: scene)
        }

        scnView?.scene = scene
    }

    /// Frames the model the way the Android renderer does at [zoomLevel], so the
    /// same value shows the same picture on both platforms.
    func setCameraZoomLevel(_ zoomLevel: Float) {
        frame(zoom: zoomLevel, fromFront: false)
    }

    /// Returns to the view shown after load: Android-style framing at [zoom], or
    /// the native starting view when no zoom was set.
    func resetCamera(zoom: Float?) {
        guard let view = scnView else { return }
        view.defaultCameraController.stopInertia()
        if let zoom = zoom {
            frame(zoom: zoom, fromFront: true)
        } else if let home = homePose, let pov = view.pointOfView,
                  let scene = view.scene, let framing = framing(of: scene) {
            pov.simdWorldTransform = home.transform
            pov.camera?.fieldOfView = home.fieldOfView
            view.defaultCameraController.target = SCNVector3(framing.target)
            view.setNeedsDisplay()
        }
    }

    /// Adds [delta] to the zoom level read from the live camera, so it also
    /// accounts for pinching. The result stays within the Android pinch range.
    func zoomBy(_ delta: Float) {
        guard delta.isFinite, let view = scnView, let scene = view.scene,
              let pov = view.pointOfView, let camera = pov.camera,
              let framing = framing(of: scene) else { return }
        let distance = simd_distance(pov.simdWorldPosition, framing.target)
        guard distance > 0 else { return }
        let current = Self.zoomLevel(
            magnification: (framing.radius * Self.halfFovTan)
                / (distance * tan(Float(camera.fieldOfView) * .pi / 360)))
        frame(zoom: min(max(current + delta, 0.5), 3.0), fromFront: false, framing: framing)
    }

    /// Saves the starting view once SceneKit has created its camera.
    /// Returns false while there is no camera yet.
    func captureHomePose() -> Bool {
        guard homePose == nil else { return true }
        guard let pov = scnView?.pointOfView, let camera = pov.camera else { return false }
        homePose = (pov.simdWorldTransform, camera.fieldOfView)
        return true
    }

    private var homePose: (transform: simd_float4x4, fieldOfView: CGFloat)?

    private func frame(
        zoom zoomLevel: Float, fromFront: Bool,
        framing known: (target: simd_float3, radius: Float)? = nil
    ) {
        guard let view = scnView, let scene = view.scene,
              zoomLevel.isFinite, zoomLevel > 0,
              let framing = known ?? framing(of: scene) else { return }
        // Below 0.3 the 45 degree field of view would pass 150 degrees.
        let zoom = max(zoomLevel, 0.3)

        let existing = view.pointOfView
        let pov = existing ?? makeCamera(in: scene)
        // A new or reset camera looks from the front, matching Android's default orbit.
        var direction = simd_float3(0, 0, 1)
        if !fromFront, let current = existing?.simdWorldPosition {
            direction = current - framing.target
        }
        if simd_length(direction) < 1e-5 { direction = simd_float3(0, 0, 1) }
        pov.simdWorldPosition = framing.target + simd_normalize(direction) * (framing.radius / zoom)
        if fromFront {
            pov.simdLook(at: framing.target, up: simd_float3(0, 1, 0), localFront: SCNNode.simdLocalFront)
        } else {
            pov.simdLook(at: framing.target)
        }
        pov.camera?.fieldOfView = CGFloat(Self.baseFieldOfView / zoom)
        pov.camera?.projectionDirection = .vertical
        pov.camera?.automaticallyAdjustsZRange = true
        view.defaultCameraController.target = SCNVector3(framing.target)
        // SceneKit's default camera is outside the scene graph, so moving it
        // does not schedule a frame on its own.
        view.setNeedsDisplay()
    }

    /// Orbit target and zoom 1.0 camera distance, mirroring
    /// CameraController.fitToBoundingBox on Android.
    private func framing(of scene: SCNScene) -> (target: simd_float3, radius: Float)? {
        guard let (lower, upper) = geometryBounds(of: scene) else { return nil }
        let maxHalfExtent = simd_reduce_max((upper - lower) / 2)
        guard maxHalfExtent > 0 else { return nil }
        let fitDistance = 2 / tan(Self.baseFieldOfView * .pi / 180 / 8)
        return ((lower + upper) / 2, fitDistance * 1.4 * maxHalfExtent / 2)
    }

    private static let halfFovTan = tan(baseFieldOfView * .pi / 360)

    /// Inverts Android's zoom, which divides both the camera distance and the
    /// field of view, so it has no closed form; magnification rises with zoom.
    private static func zoomLevel(magnification: Float) -> Float {
        func magnificationAt(_ zoom: Float) -> Float {
            zoom * halfFovTan / tan(baseFieldOfView * .pi / 360 / zoom)
        }
        var low: Float = 0.3, high: Float = 10
        let target = min(max(magnification, magnificationAt(low)), magnificationAt(high))
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if magnificationAt(mid) < target { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    private static let baseFieldOfView: Float = 45

    /// World-space bounds of the model's geometry, ignoring lights and cameras.
    private func geometryBounds(of scene: SCNScene) -> (simd_float3, simd_float3)? {
        var lower = simd_float3(repeating: .infinity)
        var upper = simd_float3(repeating: -.infinity)
        scene.rootNode.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let (minBound, maxBound) = node.boundingBox
            for corner in 0..<8 {
                let local = simd_float3(
                    corner & 1 == 0 ? minBound.x : maxBound.x,
                    corner & 2 == 0 ? minBound.y : maxBound.y,
                    corner & 4 == 0 ? minBound.z : maxBound.z)
                let world = node.simdConvertPosition(local, to: nil)
                lower = simd_min(lower, world)
                upper = simd_max(upper, world)
            }
        }
        return lower.x.isFinite ? (lower, upper) : nil
    }

    private func makeCamera(in scene: SCNScene) -> SCNNode {
        let node = SCNNode()
        node.camera = SCNCamera()
        node.name = "interactive3d_camera"
        scene.rootNode.addChildNode(node)
        scnView?.pointOfView = node
        cameraNode = node
        return node
    }

    /// Loads an HDR/EXR image as the scene background.
    ///
    /// Resizes images larger than 8192px (Metal texture limit) and applies
    /// neutral lighting to avoid HDR color tinting the model. Skipped when
    /// [useSolidBackground] is true.
    func loadHdrBackground(_ backgroundBytes: Data) throws {
        let tempPath = NSTemporaryDirectory().appending("background.hdr")
        try backgroundBytes.write(to: URL(fileURLWithPath: tempPath))
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        guard let image = UIImage(contentsOfFile: tempPath) else {
            throw NSError(domain: "SceneManager", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load HDR/EXR image"])
        }

        guard let scene = scnView?.scene else {
            throw NSError(domain: "SceneManager", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "Scene not initialized"])
        }

        if useSolidBackground { return }

        let resized = resizeIfNeeded(image, maxSize: 8192)
        scene.background.contents = resized

        // Neutral white lighting environment avoids HDR color tinting the model
        scene.lightingEnvironment.contents = UIColor.white
        scene.lightingEnvironment.intensity = 1.0

        // Replace existing lights with controlled lighting
        scene.rootNode.enumerateChildNodes { (node, _) in
            if node.light != nil { node.removeFromParentNode() }
        }
        addHdrLighting(to: scene)
    }

    /// Toggles visibility for a named group of model parts.
    func setPartGroupVisibility(group: [String: Any], isVisible: Bool) {
        guard let scene = scnView?.scene,
              let names = group["names"] as? [String] else { return }

        let opacity: CGFloat = isVisible ? 1.0 : 0.0
        scene.rootNode.enumerateChildNodes { (node, _) in
            if let nodeName = node.name, names.contains(nodeName) {
                node.opacity = opacity
                node.isHidden = !isVisible
                self.nodeOpacities[node] = opacity

                node.enumerateChildNodes { (child, _) in
                    if child.geometry != nil {
                        child.opacity = opacity
                        child.isHidden = !isVisible
                        self.nodeOpacities[child] = opacity
                    }
                }
            }
        }
        scnView?.setNeedsDisplay()
    }

    /// Deep-cleans the scene for final disposal.
    func cleanup() {
        cleanupPreviousModel()
        scnView?.scene = nil
        SCNTransaction.flush()
    }

    // MARK: - Private

    private func loadWithGLTFSceneKit(modelBytes: Data, name: String, resources: [String: Data]) throws -> SCNScene {
        // GLTFSceneKit resolves external URIs relative to the model file and reads
        // them during load, so the files only need to exist together until then.
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: dir) }

        let fileName = (name as NSString).lastPathComponent
        let modelURL = dir.appendingPathComponent(fileName.isEmpty ? "model.glb" : fileName)
        try modelBytes.write(to: modelURL)

        let root = dir.standardizedFileURL.path + "/"
        for (path, data) in resources {
            let url = dir.appendingPathComponent(path).standardizedFileURL
            guard url.path.hasPrefix(root) else { continue }
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }

        return try GLTFSceneSource(url: modelURL).scene()
    }

    private func hasLightNodes(in node: SCNNode) -> Bool {
        if node.light != nil { return true }
        return node.childNodes.contains { hasLightNodes(in: $0) }
    }

    private func addDefaultLighting(to scene: SCNScene) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.color = UIColor.white
        ambient.light!.intensity = 1000
        scene.rootNode.addChildNode(ambient)

        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light!.type = .directional
        directional.light!.color = UIColor.white
        directional.light!.intensity = 2000
        directional.position = SCNVector3(x: 10, y: 10, z: 10)
        directional.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(directional)
    }

    private func addHdrLighting(to scene: SCNScene) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.color = UIColor.white
        ambient.light!.intensity = 600
        scene.rootNode.addChildNode(ambient)

        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light!.type = .directional
        directional.light!.color = UIColor.white
        directional.light!.intensity = 1000
        directional.position = SCNVector3(x: 10, y: 10, z: 10)
        directional.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(directional)
    }

    private func resizeIfNeeded(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxSize || size.height > maxSize else { return image }

        let aspect = size.width / size.height
        let target: CGSize
        if size.width > size.height {
            target = CGSize(width: maxSize, height: maxSize / aspect)
        } else {
            target = CGSize(width: maxSize * aspect, height: maxSize)
        }

        UIGraphicsBeginImageContextWithOptions(target, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: target))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
}
