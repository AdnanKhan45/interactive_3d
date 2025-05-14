import Flutter
import UIKit
import SceneKit
import GLTFSceneKit

class Interactive3DPlatformView: NSObject, FlutterPlatformView, FlutterStreamHandler {
    private let scnView: SCNView
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?
    private var selectedNodes: Set<SCNNode> = []
    private var originalMaterials: [SCNNode: SCNMaterial] = [:]
    private var cameraNode: SCNNode?
    private var pendingPreselectedEntities: [String]?
    private var patchColors: [[String: Any]]?
    private var selectionColor: [Double]?

    init(
        frame: CGRect,
        viewId: Int64,
        messenger: FlutterBinaryMessenger,
        args: Any?
    ) {
        scnView = SCNView(frame: frame.isEmpty ? UIScreen.main.bounds : frame)
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = true
        scnView.showsStatistics = true
        scnView.backgroundColor = UIColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1.0)
        scnView.cameraControlConfiguration.allowsTranslation = false

        methodChannel = FlutterMethodChannel(
            name: "interactive_3d_\(viewId)",
            binaryMessenger: messenger
        )
        eventChannel = FlutterEventChannel(
            name: "interactive_3d_events_\(viewId)",
            binaryMessenger: messenger
        )

        super.init()

        methodChannel.setMethodCallHandler(handleMethodCall)
        eventChannel.setStreamHandler(self)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)

        let scene = SCNScene()
        scnView.scene = scene

        NSLog("SCNView initialized with frame: \(scnView.frame)")
    }

    func view() -> UIView {
        return scnView
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            guard let args = call.arguments as? [String: Any],
                  let modelBytes = (args["modelBytes"] as? FlutterStandardTypedData)?.data else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "modelBytes is required or invalid",
                    details: nil
                ))
                return
            }
            let preselectedEntities = args["preselectedEntities"] as? [String]
            let patchColors = args["patchColors"] as? [[String: Any]]
            let selectionColor = args["selectionColor"] as? [Double]

            DispatchQueue.main.async { [weak self] in
                do {
                    self?.pendingPreselectedEntities = preselectedEntities
                    self?.patchColors = patchColors
                    self?.selectionColor = selectionColor
                    try self?.loadModel(modelBytes: modelBytes)
                    result(nil)
                } catch {
                    result(FlutterError(
                        code: "LOAD_ERROR",
                        message: "Failed to load model: \(error.localizedDescription)",
                        details: error
                    ))
                }
            }

        case "setZoomLevel":
            guard let args = call.arguments as? [String: Any],
                  let zoomLevel = args["zoom"] as? Double else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "zoomLevel is required and must be a double",
                    details: nil
                ))
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.setCameraZoomLevel(zoomLevel: Float(zoomLevel))
                result(nil)
            }
            
        case "loadHdrBackground":
            guard let args = call.arguments as? [String: Any],
                  let backgroundBytes = (args["backgroundBytes"] as? FlutterStandardTypedData)?.data else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "backgroundBytes is required or invalid",
                    details: nil
                ))
                return
            }

            DispatchQueue.main.async { [weak self] in
                do {
                    try self?.loadHdrBackgroundFromBytes(backgroundBytes)
                    result(nil)
                } catch {
                    result(FlutterError(
                        code: "LOAD_ERROR",
                        message: "Failed to load HDR/EXR background: \(error.localizedDescription)",
                        details: error
                    ))
                }
            }

        case "unselectEntities":
            let entityIds = call.arguments as? [Int]
            DispatchQueue.main.async { [weak self] in
                self?.unselectEntities(entityIds: entityIds)
                result(nil)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func loadModel(modelBytes: Data) throws {
        NSLog("Received modelBytes with size: \(modelBytes.count) bytes")
        let firstBytes = modelBytes.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
        NSLog("First 16 bytes: \(firstBytes)")

        let scene: SCNScene
        do {
            let sceneSource = SCNSceneSource(data: modelBytes, options: [
                SCNSceneSource.LoadingOption.createNormalsIfAbsent: true,
                SCNSceneSource.LoadingOption.checkConsistency: true
            ])
            guard let loadedScene = sceneSource?.scene(options: nil) else {
                throw NSError(domain: "Interactive3DPlugin", code: -1, userInfo: [NSLocalizedDescriptionKey: "SCNSceneSource failed to load scene from data"])
            }
            scene = loadedScene
            NSLog("Successfully loaded GLB with SCNSceneSource")
        } catch {
            NSLog("SCNSceneSource failed: \(error.localizedDescription). Trying GLTFSceneSource.")
            let tempDir = NSTemporaryDirectory()
            let tempFilePath = tempDir.appending("model.glb")
            do {
                try modelBytes.write(to: URL(fileURLWithPath: tempFilePath))
                defer { try? FileManager.default.removeItem(atPath: tempFilePath) }
                let gltfSource = try GLTFSceneSource(url: URL(fileURLWithPath: tempFilePath))
                scene = try gltfSource.scene()
                NSLog("Successfully loaded GLB with GLTFSceneSource")
            } catch {
                NSLog("GLTFSceneSource failed: \(error.localizedDescription)")
                throw NSError(domain: "Interactive3DPlugin", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to load GLB: \(error.localizedDescription)"])
            }
        }

        var geometryCount = 0
        scene.rootNode.enumerateChildNodes { (node, _) in
            if let geometry = node.geometry {
                geometryCount += 1
                if geometry.materials.isEmpty || geometry.firstMaterial?.diffuse.contents == nil {
                    let fallbackMaterial = SCNMaterial()
                    fallbackMaterial.diffuse.contents = UIColor.green
                    fallbackMaterial.isDoubleSided = true
                    geometry.materials = [fallbackMaterial]
                    NSLog("Applied fallback green material to node: \(node.name ?? "Unnamed")")
                } else {
                    NSLog("Node: \(node.name ?? "Unnamed") has material with diffuse: \(String(describing: geometry.firstMaterial?.diffuse.contents))")
                }
            }
        }
        NSLog("Total geometry nodes: \(geometryCount)")

        if geometryCount == 0 {
            NSLog("Warning: Model has no geometry, adding blue test cube")
            let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.blue
            material.isDoubleSided = true
            box.materials = [material]
            let boxNode = SCNNode(geometry: box)
            boxNode.position = SCNVector3(0, 0, 0)
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(1, 1, 1)
            material.normal.mipFilter = .linear
            material.normal.intensity = 1.0
            
            
            scene.rootNode.addChildNode(boxNode)
        }

        if !hasLightNodes(in: scene.rootNode) {
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light!.type = .ambient
            ambientLight.light!.color = UIColor.white
            ambientLight.light!.intensity = 1000
            scene.rootNode.addChildNode(ambientLight)

            let directionalLight = SCNNode()
            directionalLight.light = SCNLight()
            directionalLight.light!.type = .directional
            directionalLight.light!.color = UIColor.white
            directionalLight.light!.intensity = 2000
            directionalLight.position = SCNVector3(x: 10, y: 10, z: 10)
            directionalLight.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(directionalLight)
            NSLog("Added default lighting")
        }

        scnView.scene = scene

        applyPreselectedEntities()

        printSceneHierarchy(scene.rootNode, level: 0)
        NSLog("Camera point of view: \(scnView.pointOfView?.name ?? "None")")
        NSLog("Scene node count: \(scene.rootNode.childNodes.count)")
        NSLog("SCNView bounds: \(scnView.bounds)")
    }

    private func applyPreselectedEntities() {
        guard let preselectedEntities = pendingPreselectedEntities, !preselectedEntities.isEmpty else {
            NSLog("No preselected entities to apply")
            return
        }

        scnView.scene?.rootNode.enumerateChildNodes { (node, _) in
            if let nodeName = node.name, preselectedEntities.contains(nodeName) {
                guard let geometryNode = findGeometryNode(in: node) else {
                    NSLog("No geometry node found for preselected: \(nodeName)")
                    return
                }
                selectedNodes.insert(node)
                applyHighlight(to: geometryNode, forNodeName: nodeName)
                NSLog("Preselected node: \(nodeName)")
            }
        }
        sendSelectionUpdate()
        pendingPreselectedEntities = nil
    }

    private func unselectEntities(entityIds: [Int]?) {
        if let ids = entityIds {
            // Unselect specific entities
            let nodesToRemove = selectedNodes.filter { ids.contains($0.hash) }
            for node in nodesToRemove {
                if let geometryNode = findGeometryNode(in: node) {
                    resetNodeColor(geometryNode)
                    selectedNodes.remove(node)
                    NSLog("Unselected node: \(node.name ?? "Unnamed")")
                }
            }
        } else {
            // Clear all selections
            for node in selectedNodes {
                if let geometryNode = findGeometryNode(in: node) {
                    resetNodeColor(geometryNode)
                    NSLog("Unselected node: \(node.name ?? "Unnamed")")
                }
            }
            selectedNodes.removeAll()
        }
        sendSelectionUpdate()
    }

    private func setCameraZoomLevel(zoomLevel: Float) {
        guard let cameraNode = cameraNode, zoomLevel > 0 else {
            NSLog("Cannot set zoom level: no camera node or invalid zoomLevel")
            return
        }
        cameraNode.position = SCNVector3(x: 0, y: 0, z: zoomLevel)
        cameraNode.camera!.zNear = 0.01
        NSLog("Updated camera zoomLevel: \(zoomLevel), position: \(cameraNode.position)")
    }

    private func hasLightNodes(in node: SCNNode) -> Bool {
        if node.light != nil {
            return true
        }
        for child in node.childNodes {
            if hasLightNodes(in: child) {
                return true
            }
        }
        return false
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        sendSelectionUpdate()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    private func sendSelectionUpdate() {
        guard let eventSink = eventSink else { return }
        let selectedEntities = selectedNodes.map { node in
            ["id": node.hash, "name": node.name ?? "Unnamed"] as [String: Any]
        }
        let event: [String: Any] = [
            "event": "selectionChanged",
            "selectedEntities": selectedEntities
        ]
        eventSink(event)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: scnView)
        let hitResults = scnView.hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])

        guard let result = hitResults.first else {
            NSLog("Tapped empty space")
            return
        }

        var targetNode: SCNNode? = result.node
        var geometryNode: SCNNode? = targetNode
        while geometryNode != nil && geometryNode!.geometry == nil {
            geometryNode = geometryNode?.childNodes.first { $0.geometry != nil }
        }
        if geometryNode == nil {
            geometryNode = findGeometryNode(in: targetNode!)
        }

        while targetNode != nil && (targetNode!.name == nil || targetNode!.name!.isEmpty || targetNode!.name!.starts(with: "Mesh.") || targetNode!.name!.hasSuffix(".001")) {
            targetNode = targetNode?.parent
        }

        let nameNode = targetNode ?? result.node
        guard let highlightNode = geometryNode else {
            NSLog("No geometry node found for: \(nameNode.name ?? "Unnamed")")
            return
        }

        if selectedNodes.contains(nameNode) {
            selectedNodes.remove(nameNode)
            resetNodeColor(highlightNode)
            NSLog("Deselected: \(nameNode.name ?? "Unnamed")")
        } else {
            selectedNodes.insert(nameNode)
            applyHighlight(to: highlightNode, forNodeName: nameNode.name)
            NSLog("Selected: \(nameNode.name ?? "Unnamed")")
        }

        sendSelectionUpdate()
    }

    private func findGeometryNode(in node: SCNNode) -> SCNNode? {
        NSLog("Checking node for geometry: \(node.name ?? "Unnamed") | Has geometry: \(node.geometry != nil)")
        if node.geometry != nil {
            NSLog("Found geometry in: \(node.name ?? "Unnamed")")
            return node
        }
        for child in node.childNodes {
            if let found = findGeometryNode(in: child) {
                return found
            }
        }
        return nil
    }

    private func getEntityColor(nodeName: String?) -> UIColor {
        // Check for patchColors first
        if let nodeName = nodeName, let patchColors = patchColors {
            for patch in patchColors {
                if let name = patch["name"] as? String, name == nodeName {
                    if let color = patch["color"] as? [Double], color.count == 4 {
                        NSLog("Matched patch color for \(nodeName): \(color)")
                        return UIColor(
                            red: CGFloat(color[0]),
                            green: CGFloat(color[1]),
                            blue: CGFloat(color[2]),
                            alpha: CGFloat(color[3])
                        )
                    }
                }
            }
        }

        // Fallback to selectionColor if provided
        if let color = selectionColor, color.count == 4 {
            NSLog("Using selectionColor: \(color)")
            return UIColor(
                red: CGFloat(color[0]),
                green: CGFloat(color[1]),
                blue: CGFloat(color[2]),
                alpha: CGFloat(color[3])
            )
        }

        // Default to red if no selectionColor is provided
        NSLog("Falling back to default red color")
        return UIColor.red
    }

    private func applyHighlight(to node: SCNNode, forNodeName nodeName: String?) {
        guard let geometry = node.geometry, let material = geometry.firstMaterial else {
            NSLog("No geometry or material for node: \(node.name ?? "Unnamed")")
            return
        }

        if originalMaterials[node] == nil {
            NSLog("Storing original material for: \(node.name ?? "Unnamed")")
            originalMaterials[node] = material.copy() as? SCNMaterial
        }

        let highlightColor = getEntityColor(nodeName: nodeName)
        material.diffuse.contents = highlightColor
        material.emission.contents = highlightColor.withAlphaComponent(0.3)
        material.multiply.contents = highlightColor
        NSLog("Applied highlight color \(highlightColor) to: \(node.name ?? "Unnamed") for nodeName: \(nodeName ?? "None")")
    }

    private func resetNodeColor(_ node: SCNNode) {
        guard let geometry = node.geometry, let material = geometry.firstMaterial else {
            NSLog("No geometry or material to reset for node: \(node.name ?? "Unnamed")")
            return
        }

        if let originalMaterial = originalMaterials[node] {
            NSLog("Restoring original material for: \(node.name ?? "Unnamed")")
            geometry.materials = [originalMaterial]
            originalMaterials.removeValue(forKey: node)
        } else {
            NSLog("No original material found for: \(node.name ?? "Unnamed")")
        }
        material.multiply.contents = UIColor.clear
    }

    private func printSceneHierarchy(_ node: SCNNode, level: Int) {
        let indent = String(repeating: "  ", count: level)
        let nodeInfo = "\(indent)Node: \(node.name ?? "Unnamed") | Geometry: \(node.geometry?.name ?? "None") | Position: \(node.position) | Bounding Box: \(node.boundingBox)"
        NSLog(nodeInfo)
        for child in node.childNodes {
            printSceneHierarchy(child, level: level + 1)
        }
    }
    
    private func loadHdrBackgroundFromBytes(_ backgroundBytes: Data) throws {
        // Write the bytes to a temporary file
        let tempDir = NSTemporaryDirectory()
        let tempFilePath = tempDir.appending("background.hdr") // Use .hdr or .exr based on input
        try backgroundBytes.write(to: URL(fileURLWithPath: tempFilePath))
        defer { try? FileManager.default.removeItem(atPath: tempFilePath) }

        // Load the HDR/EXR image
        guard let image = UIImage(contentsOfFile: tempFilePath) else {
            throw NSError(
                domain: "Interactive3DPlugin",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load HDR/EXR image"]
            )
        }

        // Maximum texture size supported by most iOS devices (Metal)
        let maxTextureSize: CGFloat = 8192

        // Check if the image exceeds the maximum texture size
        let imageSize = image.size
        var targetSize = imageSize
        if imageSize.width > maxTextureSize || imageSize.height > maxTextureSize {
            let aspectRatio = imageSize.width / imageSize.height
            if imageSize.width > imageSize.height {
                targetSize = CGSize(width: maxTextureSize, height: maxTextureSize / aspectRatio)
            } else {
                targetSize = CGSize(width: maxTextureSize * aspectRatio, height: maxTextureSize)
            }
            NSLog("Resizing HDR/EXR image from \(imageSize) to \(targetSize)")
        }

        // Resize the image if necessary
        let resizedImage: UIImage
        if targetSize != imageSize {
            UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
            defer { UIGraphicsEndImageContext() }
            image.draw(in: CGRect(origin: .zero, size: targetSize))
            guard let scaledImage = UIGraphicsGetImageFromCurrentImageContext() else {
                throw NSError(
                    domain: "Interactive3DPlugin",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to resize HDR/EXR image"]
                )
            }
            resizedImage = scaledImage
        } else {
            resizedImage = image
        }

        // Log the final image size for debugging
        let finalSize = resizedImage.size
        NSLog("Final HDR/EXR image size: \(finalSize)")

        // Ensure the scene is initialized
        guard let scene = scnView.scene else {
            throw NSError(
                domain: "Interactive3DPlugin",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Scene not initialized"]
            )
        }

        // Apply the resized image as the scene's background (visible only)
        scene.background.contents = resizedImage

        // Use a neutral white texture for the lighting environment to avoid color tint
        scene.lightingEnvironment.contents = UIColor.white
        scene.lightingEnvironment.intensity = 1.0

        // Remove any existing lights to avoid conflicts
        scene.rootNode.enumerateChildNodes { (node, _) in
            if node.light != nil {
                node.removeFromParentNode()
                NSLog("Removed existing light node: \(node.name ?? "Unnamed")")
            }
        }

        // Add a neutral ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.color = UIColor.white
        ambientLight.light!.intensity = 600 // Slightly increased for better illumination
        scene.rootNode.addChildNode(ambientLight)

        // Add a directional light for consistent model lighting
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light!.type = .directional
        directionalLight.light!.color = UIColor.white
        directionalLight.light!.intensity = 1000
        directionalLight.position = SCNVector3(x: 10, y: 10, z: 10)
        directionalLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(directionalLight)

        NSLog("Successfully loaded HDR/EXR background with size \(finalSize), applied neutral lighting")
    }
}
