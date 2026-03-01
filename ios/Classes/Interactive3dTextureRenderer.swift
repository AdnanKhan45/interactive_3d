import Flutter
import UIKit
import SceneKit
import Metal
import GLTFSceneKit

/// iOS Texture-based 3D renderer using SCNRenderer + Metal.
///
/// This replaces the PlatformView (SCNView/UiKitView) approach with Flutter's
/// TextureRegistry, rendering SceneKit into a Metal texture that Flutter composites.
///
/// Benefits over PlatformView:
/// - Instant tap response (no compositor handoff)
/// - Flutter owns the surface (same as Android Texture API)
/// - No PlatformView overhead
/// - Gesture handling through Flutter (consistent with Android)
class Interactive3dTextureRendererIOS: NSObject, FlutterStreamHandler {
    
    private static let TAG = "Interactive3dTexIOS"
    
    // Metal + SceneKit
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var renderer: SCNRenderer?
    private var scene: SCNScene?
    
    // Flutter texture bridge
    private var textureRegistry: FlutterTextureRegistry?
    private var textureId: Int64 = -1
    private var pixelBuffer: CVPixelBuffer?
    private var metalTextureCache: CVMetalTextureCache?
    
    // Render loop
    private var displayLink: CADisplayLink?
    private var isRendering = false
    private let startTime = CACurrentMediaTime()
    
    // Dimensions
    private var width: Int
    private var height: Int
    
    // Camera
    private var cameraNode: SCNNode?
    private var orbitAngleX: Float = 0.3
    private var orbitAngleY: Float = 0.5
    private var orbitRadius: Float = 5.0
    private var zoomLevel: Float = 1.0
    private let defaultFOV: Double = 60.0
    
    // Selection
    private var selectedNodes: Set<SCNNode> = []
    private var originalMaterials: [SCNNode: SCNMaterial] = [:]
    private var selectionColor: [Double]?
    private var patchColors: [[String: Any]]?
    private var pendingPreselectedEntities: [String]?
    private var clearSelectionsOnHighlight: Bool = false
    private var nodeOpacities: [SCNNode: CGFloat] = [:]
    
    // Cache
    private var cacheManager: Interactive3DCacheManager?
    private var enableCache: Bool = false
    private var cacheColor: UIColor = UIColor(red: 0.8, green: 0.8, blue: 0.2, alpha: 0.6)
    private var modelCacheKey: String = ""
    
    // Sequence
    struct SequenceConfig {
        let group: String
        let order: [String]
        let bidirectional: Bool
        let tiedGroup: String?
    }
    private var sequenceConfigs: [SequenceConfig] = []
    private var allowedNext: [String: Set<String>] = [:]
    private var startNodes: Set<String> = []
    
    // Background
    private var useSolidBackground = false
    private var solidBackgroundColor: UIColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
    
    // Events
    private var eventSink: FlutterEventSink?
    
    // Idle tracking
    private var isInteracting = false
    private var idleFrameCount = 0
    private var frameCount = 0
    
    // Dispose
    private var isDisposed = false
    
    // Selection listener (for plugin routing)
    var onSelectionChanged: (([[String: Any]]) -> Void)?
    var onCacheSelectionChanged: (([[String: Any]]) -> Void)?
    
    init(width: Int, height: Int) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        super.init()
        initializeMetal()
    }
    
    // MARK: - Metal Initialization
    
    private func initializeMetal() {
        guard let mtlDevice = MTLCreateSystemDefaultDevice() else {
            NSLog("\(Interactive3dTextureRendererIOS.TAG): Failed to create Metal device")
            return
        }
        device = mtlDevice
        commandQueue = mtlDevice.makeCommandQueue()
        
        // Create SCNRenderer with Metal device
        renderer = SCNRenderer(device: mtlDevice, options: nil)
        renderer?.autoenablesDefaultLighting = false
        
        // Create Metal texture cache for CVPixelBuffer → MTLTexture conversion
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, mtlDevice, nil, &cache)
        metalTextureCache = cache
        
        NSLog("\(Interactive3dTextureRendererIOS.TAG): Metal initialized")
    }
    
    // MARK: - Flutter Texture Registration
    
    func registerTexture(with registry: FlutterTextureRegistry) -> Int64 {
        textureRegistry = registry
        
        // Create the pixel buffer that Flutter will read from
        createPixelBuffer()
        
        // Register as a Flutter texture source
        textureId = registry.register(self)
        
        NSLog("\(Interactive3dTextureRendererIOS.TAG): Registered texture ID: \(textureId) (\(width)x\(height))")
        return textureId
    }
    
    private func createPixelBuffer() {
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )
        
        if status == kCVReturnSuccess {
            pixelBuffer = buffer
            NSLog("\(Interactive3dTextureRendererIOS.TAG): Created pixel buffer \(width)x\(height)")
        } else {
            NSLog("\(Interactive3dTextureRendererIOS.TAG): Failed to create pixel buffer: \(status)")
        }
    }
    
    // MARK: - Render Loop
    
    func startRenderLoop() {
        guard !isRendering else { return }
        isRendering = true
        
        displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        } else {
            // Fallback on earlier versions
        }
        displayLink?.add(to: .main, forMode: .common)
        
        NSLog("\(Interactive3dTextureRendererIOS.TAG): Render loop started")
    }
    
    func stopRenderLoop() {
        isRendering = false
        displayLink?.invalidate()
        displayLink = nil
        NSLog("\(Interactive3dTextureRendererIOS.TAG): Render loop stopped")
    }
    
    @objc private func renderFrame() {
        guard isRendering, !isDisposed else { return }
        
        // Adaptive frame pacing
        if !isInteracting {
            idleFrameCount += 1
            if idleFrameCount > 90 { return } // fully idle
            if idleFrameCount > 30 && frameCount % 2 != 0 { return } // 30fps idle
        }
        
        guard let renderer = renderer,
              let scene = scene,
              let commandQueue = commandQueue,
              let pixelBuffer = pixelBuffer,
              let metalTextureCache = metalTextureCache else { return }
        
        renderer.scene = scene
        
        // Get Metal texture from CVPixelBuffer
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            metalTextureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard status == kCVReturnSuccess, let cvTex = cvTexture,
              let metalTexture = CVMetalTextureGetTexture(cvTex) else { return }
        
        // Create render pass descriptor targeting our texture
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = metalTexture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        
        // Set clear color
        if useSolidBackground {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            solidBackgroundColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        } else {
            passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Render
        let viewport = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        renderer.render(atTime: CACurrentMediaTime() - startTime,
                       viewport: viewport,
                       commandBuffer: commandBuffer,
                       passDescriptor: passDescriptor)
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Notify Flutter that texture has new content
        textureRegistry?.textureFrameAvailable(textureId)
        
        frameCount += 1
    }
    
    // MARK: - Scene Setup
    
    func loadModel(modelBytes: Data,
                   preselectedEntities: [String]?,
                   selectionColor: [Double]?,
                   patchColors: [[String: Any]]?,
                   clearSelectionsOnHighlight: Bool,
                   enableCache: Bool,
                   cacheColor: [Double]?,
                   modelName: String?,
                   sequenceConfigs: [[String: Any]]?,
                   backgroundColor: [Double]?) {
        
        // Store params
        self.selectionColor = selectionColor
        self.patchColors = patchColors
        self.clearSelectionsOnHighlight = clearSelectionsOnHighlight
        self.pendingPreselectedEntities = preselectedEntities
        
        // Handle background color
        if let bgColor = backgroundColor, bgColor.count >= 3 {
            useSolidBackground = true
            let alpha = bgColor.count >= 4 ? CGFloat(bgColor[3]) : 1.0
            solidBackgroundColor = UIColor(
                red: CGFloat(bgColor[0]),
                green: CGFloat(bgColor[1]),
                blue: CGFloat(bgColor[2]),
                alpha: alpha
            )
        }
        
        // Handle sequence configs
        if let seqArray = sequenceConfigs {
            self.sequenceConfigs = seqArray.compactMap { dict in
                guard let group = dict["group"] as? String,
                      let order = dict["order"] as? [String],
                      let bidirectional = dict["bidirectional"] as? Bool else { return nil }
                let tiedGroup = dict["tiedGroup"] as? String
                return SequenceConfig(group: group, order: order, bidirectional: bidirectional, tiedGroup: tiedGroup)
            }
            buildSequenceMaps()
        }
        
        // Handle cache
        self.enableCache = enableCache
        if let cc = cacheColor, cc.count == 4 {
            self.cacheColor = UIColor(red: CGFloat(cc[0]), green: CGFloat(cc[1]), blue: CGFloat(cc[2]), alpha: CGFloat(cc[3]))
        }
        self.modelCacheKey = modelName ?? UUID().uuidString
        if enableCache {
            cacheManager = Interactive3DCacheManager(modelKey: modelCacheKey, cacheColor: self.cacheColor)
            cacheManager?.onCacheChanged = { [weak self] _ in
                self?.sendCacheSelectionUpdate()
            }
        }
        
        // Clean previous
        cleanupPreviousModel()
        
        // Load scene
        do {
            let loadedScene = try loadSceneFromBytes(modelBytes)
            scene = loadedScene
            renderer?.scene = loadedScene
            
            setupCamera()
            setupDefaultLighting()
            
            // Apply cache highlights
            if enableCache, let cacheMgr = cacheManager {
                for cachedName in cacheMgr.cachedEntities {
                    loadedScene.rootNode.enumerateChildNodes { (node, _) in
                        if let nodeName = node.name, nodeName == cachedName,
                           let geometryNode = findGeometryNode(in: node) {
                            applyCacheHighlight(to: geometryNode, forNodeName: nodeName)
                        }
                    }
                }
                sendCacheSelectionUpdate()
            }
            
            applyPreselectedEntities()
            
            NSLog("\(Interactive3dTextureRendererIOS.TAG): Model loaded successfully")
        } catch {
            NSLog("\(Interactive3dTextureRendererIOS.TAG): Failed to load model: \(error)")
        }
    }
    
    private func loadSceneFromBytes(_ modelBytes: Data) throws -> SCNScene {
        // Try SCNSceneSource first
        do {
            let sceneSource = SCNSceneSource(data: modelBytes, options: [
                SCNSceneSource.LoadingOption.createNormalsIfAbsent: true,
                SCNSceneSource.LoadingOption.checkConsistency: true
            ])
            if let loadedScene = sceneSource?.scene(options: nil) {
                NSLog("\(Interactive3dTextureRendererIOS.TAG): Loaded with SCNSceneSource")
                applyFallbackMaterials(to: loadedScene)
                return loadedScene
            }
        } catch {
            NSLog("\(Interactive3dTextureRendererIOS.TAG): SCNSceneSource failed: \(error)")
        }
        
        // Fallback to GLTFSceneSource
        let tempPath = NSTemporaryDirectory().appending("model.glb")
        try modelBytes.write(to: URL(fileURLWithPath: tempPath))
        defer { try? FileManager.default.removeItem(atPath: tempPath) }
        
        let gltfSource = try GLTFSceneSource(url: URL(fileURLWithPath: tempPath))
        let loadedScene = try gltfSource.scene()
        NSLog("\(Interactive3dTextureRendererIOS.TAG): Loaded with GLTFSceneSource")
        applyFallbackMaterials(to: loadedScene)
        return loadedScene
    }
    
    private func applyFallbackMaterials(to scene: SCNScene) {
        scene.rootNode.enumerateChildNodes { (node, _) in
            if let geometry = node.geometry {
                if geometry.materials.isEmpty || geometry.firstMaterial?.diffuse.contents == nil {
                    let fallbackMaterial = SCNMaterial()
                    fallbackMaterial.diffuse.contents = UIColor.green
                    fallbackMaterial.isDoubleSided = true
                    geometry.materials = [fallbackMaterial]
                }
            }
        }
    }
    
    // MARK: - Camera
    
    private func setupCamera() {
        guard let scene = scene else { return }
        
        // Remove existing cameras
        cameraNode?.removeFromParentNode()
        
        let camera = SCNCamera()
        camera.zNear = 0.001
        camera.zFar = 1000
        camera.fieldOfView = CGFloat(defaultFOV / Double(zoomLevel))
        
        let camNode = SCNNode()
        camNode.camera = camera
        camNode.name = "interactive3d_camera"
        scene.rootNode.addChildNode(camNode)
        cameraNode = camNode
        renderer?.pointOfView = camNode
        
        // Auto-fit to model bounds
        let (minBound, maxBound) = scene.rootNode.boundingBox
        let center = SCNVector3(
            (minBound.x + maxBound.x) / 2,
            (minBound.y + maxBound.y) / 2,
            (minBound.z + maxBound.z) / 2
        )
        let size = SCNVector3(
            maxBound.x - minBound.x,
            maxBound.y - minBound.y,
            maxBound.z - minBound.z
        )
        let maxDim = max(size.x, max(size.y, size.z))
        orbitRadius = maxDim * 2.0
        
        updateCameraPosition()
    }
    
    private func updateCameraPosition() {
        guard let camNode = cameraNode else { return }
        
        let x = orbitRadius * cos(orbitAngleX) * sin(orbitAngleY)
        let y = orbitRadius * sin(orbitAngleX)
        let z = orbitRadius * cos(orbitAngleX) * cos(orbitAngleY)
        
        camNode.position = SCNVector3(x, y, z)
        camNode.look(at: SCNVector3Zero)
        
        camNode.camera?.fieldOfView = CGFloat(defaultFOV / Double(zoomLevel))
    }
    
    // MARK: - Lighting
    
    private func setupDefaultLighting() {
        guard let scene = scene else { return }
        
        // Check if scene already has lights
        var hasLights = false
        scene.rootNode.enumerateChildNodes { (node, stop) in
            if node.light != nil { hasLights = true; stop.pointee = true }
        }
        if hasLights { return }
        
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.color = UIColor.white
        ambientLight.light!.intensity = 1000
        ambientLight.name = "interactive3d_ambient"
        scene.rootNode.addChildNode(ambientLight)
        
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light!.type = .directional
        directionalLight.light!.color = UIColor.white
        directionalLight.light!.intensity = 2000
        directionalLight.position = SCNVector3(x: 10, y: 10, z: 10)
        directionalLight.look(at: SCNVector3Zero)
        directionalLight.name = "interactive3d_directional"
        scene.rootNode.addChildNode(directionalLight)
    }
    
    // MARK: - HDR Background
    
    func loadHdrBackground(_ backgroundBytes: Data) throws {
        guard let scene = scene else {
            throw NSError(domain: "Interactive3dTexIOS", code: -5, userInfo: [NSLocalizedDescriptionKey: "Scene not initialized"])
        }
        
        // Skip if using solid background
        if useSolidBackground {
            NSLog("\(Interactive3dTextureRendererIOS.TAG): Skipping HDR — using solid background")
            return
        }
        
        let tempPath = NSTemporaryDirectory().appending("background.hdr")
        try backgroundBytes.write(to: URL(fileURLWithPath: tempPath))
        defer { try? FileManager.default.removeItem(atPath: tempPath) }
        
        guard let image = UIImage(contentsOfFile: tempPath) else {
            throw NSError(domain: "Interactive3dTexIOS", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to load HDR image"])
        }
        
        // Resize if needed
        let maxSize: CGFloat = 8192
        var targetSize = image.size
        if image.size.width > maxSize || image.size.height > maxSize {
            let ratio = image.size.width / image.size.height
            targetSize = image.size.width > image.size.height
                ? CGSize(width: maxSize, height: maxSize / ratio)
                : CGSize(width: maxSize * ratio, height: maxSize)
        }
        
        let finalImage: UIImage
        if targetSize != image.size {
            UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
            defer { UIGraphicsEndImageContext() }
            image.draw(in: CGRect(origin: .zero, size: targetSize))
            finalImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        } else {
            finalImage = image
        }
        
        scene.background.contents = finalImage
        scene.lightingEnvironment.contents = UIColor.white
        scene.lightingEnvironment.intensity = 1.0
        
        // Replace lights for HDR
        scene.rootNode.enumerateChildNodes { (node, _) in
            if node.light != nil && (node.name?.hasPrefix("interactive3d_") == true) {
                node.removeFromParentNode()
            }
        }
        
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.color = UIColor.white
        ambientLight.light!.intensity = 600
        ambientLight.name = "interactive3d_ambient"
        scene.rootNode.addChildNode(ambientLight)
        
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light!.type = .directional
        directionalLight.light!.color = UIColor.white
        directionalLight.light!.intensity = 1000
        directionalLight.position = SCNVector3(x: 10, y: 10, z: 10)
        directionalLight.look(at: SCNVector3Zero)
        directionalLight.name = "interactive3d_directional"
        scene.rootNode.addChildNode(directionalLight)
        
        NSLog("\(Interactive3dTextureRendererIOS.TAG): HDR background loaded")
    }
    
    // MARK: - Gestures (called from plugin)
    
    func onTap(x: Float, y: Float) {
        isInteracting = true
        idleFrameCount = 0
        
        guard let renderer = renderer, let scene = scene else { return }
        
        // Normalize coordinates to 0..1
        let normalizedX = CGFloat(x) / CGFloat(width)
        let normalizedY = CGFloat(y) / CGFloat(height)
        let point = CGPoint(x: normalizedX * CGFloat(width), y: normalizedY * CGFloat(height))
        
        let hitResults = renderer.hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.all.rawValue
        ])
        
        guard let result = hitResults.first else {
            NSLog("\(Interactive3dTextureRendererIOS.TAG): Tapped empty space")
            scheduleIdleAfterDelay()
            return
        }
        
        // Walk up to find named node
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
        
        guard let nameNode = targetNode, let nodeName = nameNode.name else {
            scheduleIdleAfterDelay()
            return
        }
        guard let geoNode = findGeometryNode(in: nameNode) else {
            scheduleIdleAfterDelay()
            return
        }
        
        guard isTapAllowed(nodeName) else {
            NSLog("\(Interactive3dTextureRendererIOS.TAG): Tap rejected: \(nodeName)")
            eventSink?(["event": "selectionRejected", "name": nodeName])
            scheduleIdleAfterDelay()
            return
        }
        
        // Cached entity tap → remove from cache
        if enableCache, let cacheMgr = cacheManager, cacheMgr.isCached(nodeName) {
            cacheMgr.removeFromCache(nodeName)
            resetNodeColor(geoNode)
            sendCacheSelectionUpdate()
            if selectedNodes.contains(nameNode) {
                selectedNodes.remove(nameNode)
                sendSelectionUpdate()
            }
            scheduleIdleAfterDelay()
            return
        }
        
        // Toggle selection
        if selectedNodes.contains(nameNode) {
            selectedNodes.remove(nameNode)
            resetNodeColor(geoNode)
        } else {
            selectedNodes.insert(nameNode)
            applyHighlight(to: geoNode, forNodeName: nodeName)
            if enableCache {
                cacheManager?.addToCache(nodeName)
            }
        }
        
        sendSelectionUpdate()
        scheduleIdleAfterDelay()
    }
    
    func onPan(deltaX: Float, deltaY: Float) {
        isInteracting = true
        idleFrameCount = 0
        
        orbitAngleY -= deltaX * 0.02
        orbitAngleX += deltaY * 0.02
        orbitAngleX = max(-1.4, min(1.4, orbitAngleX))
        updateCameraPosition()
        
        scheduleIdleAfterDelay()
    }
    
    func onScale(scale: Float) {
        isInteracting = true
        idleFrameCount = 0
        
        let factor: Float
        if scale > 1.0 {
            factor = 1.0 + (scale - 1.0) * 0.15
        } else {
            factor = 1.0 - (1.0 - scale) * 0.15
        }
        
        zoomLevel *= factor
        zoomLevel = max(0.5, min(3.0, zoomLevel))
        updateCameraPosition()
        
        scheduleIdleAfterDelay()
    }
    
    private func scheduleIdleAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isInteracting = false
            self?.idleFrameCount = 0
        }
    }
    
    // MARK: - Zoom
    
    func setCameraZoomLevel(_ zoom: Float) {
        zoomLevel = zoom
        updateCameraPosition()
    }
    
    // MARK: - Viewport
    
    func updateViewport(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        self.width = width
        self.height = height
        createPixelBuffer()
    }
    
    // MARK: - Selection helpers (same logic as PlatformView version)
    
    private func findGeometryNode(in node: SCNNode) -> SCNNode? {
        if node.geometry != nil { return node }
        for child in node.childNodes {
            if let found = findGeometryNode(in: child) { return found }
        }
        return nil
    }
    
    private func getEntityColor(nodeName: String?) -> UIColor {
        if let nodeName = nodeName, let patchColors = patchColors {
            for patch in patchColors {
                if let name = patch["name"] as? String, name == nodeName,
                   let color = patch["color"] as? [Double], color.count == 4 {
                    return UIColor(red: CGFloat(color[0]), green: CGFloat(color[1]), blue: CGFloat(color[2]), alpha: CGFloat(color[3]))
                }
            }
        }
        if let color = selectionColor, color.count == 4 {
            return UIColor(red: CGFloat(color[0]), green: CGFloat(color[1]), blue: CGFloat(color[2]), alpha: CGFloat(color[3]))
        }
        return UIColor.red
    }
    
    private func applyHighlight(to node: SCNNode, forNodeName nodeName: String?) {
        guard let geometry = node.geometry, let material = geometry.firstMaterial else { return }
        if originalMaterials[node] == nil {
            originalMaterials[node] = material.copy() as? SCNMaterial
        }
        let color = getEntityColor(nodeName: nodeName)
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.3)
        material.multiply.contents = color
    }
    
    private func applyCacheHighlight(to node: SCNNode, forNodeName nodeName: String?) {
        guard let geometry = node.geometry, let material = geometry.firstMaterial else { return }
        if originalMaterials[node] == nil {
            originalMaterials[node] = material.copy() as? SCNMaterial
        }
        material.diffuse.contents = cacheColor
        material.emission.contents = cacheColor.withAlphaComponent(0.2)
        material.multiply.contents = cacheColor
    }
    
    private func resetNodeColor(_ node: SCNNode) {
        guard let geometry = node.geometry else { return }
        if let originalMaterial = originalMaterials[node] {
            geometry.materials = [originalMaterial.copy() as! SCNMaterial]
            originalMaterials.removeValue(forKey: node)
        }
    }
    
    private func applyPreselectedEntities() {
        guard let preselected = pendingPreselectedEntities, !preselected.isEmpty, let scene = scene else { return }
        scene.rootNode.enumerateChildNodes { (node, _) in
            if let nodeName = node.name, preselected.contains(nodeName),
               let geoNode = findGeometryNode(in: node) {
                selectedNodes.insert(node)
                applyHighlight(to: geoNode, forNodeName: nodeName)
            }
        }
        sendSelectionUpdate()
        pendingPreselectedEntities = nil
    }
    
    // MARK: - Sequence
    
    private func buildSequenceMaps() {
        allowedNext.removeAll()
        for config in sequenceConfigs {
            let list = config.order
            for (i, name) in list.enumerated() where i < list.count - 1 {
                allowedNext[name, default: []].insert(list[i + 1])
                if config.bidirectional {
                    allowedNext[list[i + 1], default: []].insert(name)
                }
            }
        }
    }
    
    private func isTapAllowed(_ nodeName: String) -> Bool {
        if selectedNodes.contains(where: { $0.name == nodeName }) { return true }
        guard let config = sequenceConfigs.first(where: { $0.order.contains(nodeName) }),
              let idx = config.order.firstIndex(of: nodeName) else { return true }
        
        let selectedInGroup = selectedNodes.compactMap { $0.name }.filter { config.order.contains($0) }
        
        var selectedInTied: [String] = []
        if let tiedName = config.tiedGroup,
           let tiedConfig = sequenceConfigs.first(where: { $0.group == tiedName }) {
            selectedInTied = selectedNodes.compactMap { $0.name }.filter { tiedConfig.order.contains($0) }
        }
        
        if selectedInGroup.isEmpty {
            if !selectedInTied.isEmpty,
               let tiedName = config.tiedGroup,
               let tiedConfig = sequenceConfigs.first(where: { $0.group == tiedName }) {
                return selectedInTied.contains(tiedConfig.order[idx])
            }
            return true
        }
        
        for name in selectedInGroup {
            if allowedNext[name]?.contains(nodeName) == true { return true }
        }
        return false
    }
    
    // MARK: - Part Visibility
    
    func setPartGroupVisibility(group: [String: Any], isVisible: Bool) {
        guard let scene = scene, let names = group["names"] as? [String] else { return }
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
    }
    
    // MARK: - Unselect
    
    func unselectEntities(entityIds: [Int]?) {
        if let ids = entityIds {
            let nodesToRemove = selectedNodes.filter { ids.contains($0.hash) }
            for node in nodesToRemove {
                if let geoNode = findGeometryNode(in: node) { resetNodeColor(geoNode) }
                selectedNodes.remove(node)
            }
        } else {
            for node in selectedNodes {
                if let geoNode = findGeometryNode(in: node) { resetNodeColor(geoNode) }
            }
            selectedNodes.removeAll()
        }
        sendSelectionUpdate()
    }
    
    // MARK: - Cache
    
    func clearCache() {
        guard enableCache, let cacheMgr = cacheManager, let scene = scene else { return }
        let entitiesToClear = Array(cacheMgr.cachedEntities)
        cacheMgr.clearCache()
        scene.rootNode.enumerateChildNodes { (node, _) in
            if let nodeName = node.name, entitiesToClear.contains(nodeName),
               let geoNode = findGeometryNode(in: node) {
                resetNodeColor(geoNode)
            }
        }
        sendCacheSelectionUpdate()
    }
    
    func refreshCacheHighlights() {
        guard let scene = scene else { return }
        scene.rootNode.enumerateChildNodes { (node, _) in
            if let geoNode = findGeometryNode(in: node) { resetNodeColor(geoNode) }
        }
        var cachedSet = Set<String>()
        if enableCache, let cacheMgr = cacheManager {
            for name in cacheMgr.cachedEntities {
                cachedSet.insert(name)
                scene.rootNode.enumerateChildNodes { (node, _) in
                    if let nodeName = node.name, nodeName == name,
                       let geoNode = findGeometryNode(in: node) {
                        applyCacheHighlight(to: geoNode, forNodeName: nodeName)
                    }
                }
            }
        }
        for node in selectedNodes {
            if let name = node.name, !cachedSet.contains(name),
               let geoNode = findGeometryNode(in: node) {
                applyHighlight(to: geoNode, forNodeName: name)
            }
        }
        if clearSelectionsOnHighlight {
            selectedNodes.removeAll()
            sendSelectionUpdate()
        }
    }
    
    func removeFromCache(names: [String]) {
        guard let scene = scene else { return }
        for name in names {
            cacheManager?.removeFromCache(name)
            if let node = scene.rootNode.childNode(withName: name, recursively: true) {
                selectedNodes.remove(node)
                if let geoNode = findGeometryNode(in: node) { resetNodeColor(geoNode) }
            }
        }
        sendSelectionUpdate()
        sendCacheSelectionUpdate()
    }
    
    // MARK: - Events
    
    private func sendSelectionUpdate() {
        let entities = selectedNodes.map { node in
            ["id": node.hash, "name": node.name ?? "Unnamed"] as [String: Any]
        }
        eventSink?(["event": "selectionChanged", "selectedEntities": entities])
        onSelectionChanged?(entities)
    }
    
    private func sendCacheSelectionUpdate() {
        guard enableCache, let cacheMgr = cacheManager else { return }
        let entities = cacheMgr.cachedEntities.map { ["name": $0] }
        eventSink?(["event": "cacheSelectionChanged", "cachedEntities": entities])
        onCacheSelectionChanged?(entities)
    }
    
    // MARK: - FlutterStreamHandler
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        sendSelectionUpdate()
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    // MARK: - Cleanup
    
    private func cleanupPreviousModel() {
        selectedNodes.removeAll()
        originalMaterials.removeAll()
        nodeOpacities.removeAll()
        
        if let currentScene = scene {
            currentScene.rootNode.enumerateChildNodes { (node, _) in
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
            currentScene.background.contents = nil
            currentScene.lightingEnvironment.contents = nil
        }
        SCNTransaction.flush()
        pendingPreselectedEntities = nil
        cameraNode = nil
    }
    
    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        
        stopRenderLoop()
        
        // Clean scene
        cleanupPreviousModel()
        scene = nil
        renderer?.scene = nil
        renderer = nil
        
        // Release texture
        if textureId >= 0 {
            textureRegistry?.unregisterTexture(textureId)
        }
        pixelBuffer = nil
        metalTextureCache = nil
        
        // Clear state
        eventSink = nil
        commandQueue = nil
        device = nil
        cacheManager = nil
        sequenceConfigs.removeAll()
        allowedNext.removeAll()
        
        SCNTransaction.flush()
        
        NSLog("\(Interactive3dTextureRendererIOS.TAG): Disposed")
    }
    
    deinit {
        dispose()
    }
}

// MARK: - FlutterTexture conformance

extension Interactive3dTextureRendererIOS: FlutterTexture {
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pixelBuffer = pixelBuffer else { return nil }
        return Unmanaged.passRetained(pixelBuffer)
    }
}
