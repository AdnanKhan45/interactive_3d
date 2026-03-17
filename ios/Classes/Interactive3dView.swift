import Flutter
import UIKit
import SceneKit

/// The main platform view for the interactive_3d plugin on iOS.
///
/// Owns the SCNView and coordinates sub-managers for scene loading
/// ([SceneManager]), entity selection ([SelectionHandler]), and
/// sequence validation ([SequenceValidator]). Method calls from Dart
/// are dispatched to the appropriate manager.
class Interactive3DPlatformView: NSObject, FlutterPlatformView, FlutterStreamHandler {

    private let scnView: SCNView
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?

    // Sub-managers
    private let sceneManager: SceneManager
    private let selection: SelectionHandler
    private let sequenceValidator: SequenceValidator

    // State
    private var pendingPreselectedEntities: [String]?
    private var isDisposed = false

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: Any?) {
        scnView = SCNView(frame: frame.isEmpty ? UIScreen.main.bounds : frame)
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = true
        scnView.showsStatistics = false
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

        sceneManager = SceneManager(scnView: scnView)
        selection = SelectionHandler()
        sequenceValidator = SequenceValidator()

        super.init()

        // Use [weak self] to break retain cycle with method channel
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
        // Wrap in WeakStreamHandler to break retain cycle with event channel
        eventChannel.setStreamHandler(WeakStreamHandler(delegate: self))

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)

        scnView.scene = SCNScene()
    }

    func view() -> UIView {
        return scnView
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        sendSelectionUpdate()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - Method Dispatch

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            handleLoadModel(call, result: result)
        case "setZoomLevel":
            handleSetZoomLevel(call, result: result)
        case "loadHdrBackground":
            handleLoadHdrBackground(call, result: result)
        case "unselectEntities":
            handleUnselectEntities(call, result: result)
        case "setPartGroupVisibility":
            handleSetPartGroupVisibility(call, result: result)
        case "clearCache":
            handleClearCache(result: result)
        case "refreshCacheHighlights":
            handleRefreshCacheHighlights(result: result)
        case "removeFromCache":
            handleRemoveFromCache(call, result: result)
        case "dispose":
            DispatchQueue.main.async { [weak self] in
                self?.dispose()
                result(nil)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Method Handlers

    private func handleLoadModel(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelBytes = (args["modelBytes"] as? FlutterStandardTypedData)?.data else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "modelBytes required", details: nil))
            return
        }

        // Configure selection
        selection.selectionColor = args["selectionColor"] as? [Double]
        selection.patchColors = args["patchColors"] as? [[String: Any]]
        selection.clearSelectionsOnHighlight = (args["clearSelectionsOnHighlight"] as? Bool) ?? false
        pendingPreselectedEntities = args["preselectedEntities"] as? [String]

        // Configure sequence
        if let seqArray = args["selectionSequence"] as? [[String: Any]] {
            sequenceValidator.configure(from: seqArray)
        }

        // Configure cache
        selection.enableCache = (args["enableCache"] as? Bool) ?? false
        if let cacheColorArray = args["cacheColor"] as? [Double], cacheColorArray.count == 4 {
            selection.cacheColor = UIColor(
                red: CGFloat(cacheColorArray[0]),
                green: CGFloat(cacheColorArray[1]),
                blue: CGFloat(cacheColorArray[2]),
                alpha: CGFloat(cacheColorArray[3])
            )
        }
        let modelCacheKey = (args["name"] as? String) ?? UUID().uuidString
        if selection.enableCache {
            selection.cacheManager = Interactive3DCacheManager(
                modelKey: modelCacheKey, cacheColor: selection.cacheColor
            )
            selection.cacheManager?.onCacheChanged = { [weak self] _ in
                self?.sendCacheSelectionUpdate()
            }
        } else {
            selection.cacheManager = nil
        }

        // Configure background
        if let bgColor = args["backgroundColor"] as? [Double], bgColor.count >= 3 {
            let alpha = bgColor.count >= 4 ? CGFloat(bgColor[3]) : 1.0
            sceneManager.useSolidBackground = true
            scnView.backgroundColor = UIColor(
                red: CGFloat(bgColor[0]),
                green: CGFloat(bgColor[1]),
                blue: CGFloat(bgColor[2]),
                alpha: alpha
            )
        } else {
            sceneManager.useSolidBackground = false
        }

        // Reset previous selection state
        selection.reset()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.sceneManager.loadModel(modelBytes: modelBytes)

                // Apply cache highlights
                if let scene = self.scnView.scene {
                    self.selection.highlightCachedEntities(in: scene)
                }
                self.sendCacheSelectionUpdate()

                // Apply preselections
                self.applyPreselectedEntities()

                result(nil)
            } catch {
                result(FlutterError(code: "LOAD_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func handleSetZoomLevel(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let zoom = args["zoom"] as? Double else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "zoom required", details: nil))
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.sceneManager.setCameraZoomLevel(Float(zoom))
            result(nil)
        }
    }

    private func handleLoadHdrBackground(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let bgBytes = (args["backgroundBytes"] as? FlutterStandardTypedData)?.data else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "backgroundBytes required", details: nil))
            return
        }
        DispatchQueue.main.async { [weak self] in
            do {
                try self?.sceneManager.loadHdrBackground(bgBytes)
                result(nil)
            } catch {
                result(FlutterError(code: "LOAD_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func handleUnselectEntities(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let entityIds = call.arguments as? [Int]
        DispatchQueue.main.async { [weak self] in
            self?.selection.unselectEntities(entityIds: entityIds)
            self?.sendSelectionUpdate()
            result(nil)
        }
    }

    private func handleSetPartGroupVisibility(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let group = args["group"] as? [String: Any],
              let visibility = args["visibility"] as? [String: Bool],
              let title = group["title"] as? String,
              let isVisible = visibility[title] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid group or visibility", details: nil))
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.sceneManager.setPartGroupVisibility(group: group, isVisible: isVisible)
            result(nil)
        }
    }

    private func handleClearCache(result: @escaping FlutterResult) {
        guard let scene = scnView.scene else {
            result(FlutterError(code: "CACHE_DISABLED", message: "No scene", details: nil))
            return
        }
        selection.clearCache(in: scene)
        sendCacheSelectionUpdate()
        result(nil)
    }

    private func handleRefreshCacheHighlights(result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let scene = self.scnView.scene else {
                result(nil)
                return
            }
            self.selection.refreshAllHighlights(in: scene)
            self.sendSelectionUpdate()
            self.sendCacheSelectionUpdate()
            result(nil)
        }
    }

    private func handleRemoveFromCache(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let names = call.arguments as? [String] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "names required", details: nil))
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let scene = self.scnView.scene else {
                result(nil)
                return
            }
            self.selection.removeFromCache(names: names, in: scene)
            self.sendSelectionUpdate()
            self.sendCacheSelectionUpdate()
            result(nil)
        }
    }

    // MARK: - Tap Handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: scnView)
        let hitResults = scnView.hitTest(location, options: [
            .searchMode: SCNHitTestSearchMode.all.rawValue
        ])
        guard let hit = hitResults.first else { return }

        // Walk up the hierarchy to find the named parent node
        var targetNode: SCNNode? = hit.node
        while targetNode != nil &&
              (targetNode!.name == nil ||
               targetNode!.name!.isEmpty ||
               targetNode!.name!.starts(with: "Mesh.") ||
               targetNode!.name!.hasSuffix(".001")) {
            targetNode = targetNode?.parent
        }

        guard let nameNode = targetNode, let nodeName = nameNode.name else { return }
        guard let geometryNode = selection.findGeometryNode(in: nameNode) else { return }

        // Sequence validation
        guard sequenceValidator.isTapAllowed(nodeName, selectedNodes: selection.selectedNodes) else {
            eventSink?(["event": "selectionRejected", "name": nodeName])
            return
        }

        // If cached, remove from cache and deselect
        if selection.enableCache,
           let cacheMgr = selection.cacheManager,
           cacheMgr.isCached(nodeName) {
            cacheMgr.removeFromCache(nodeName)
            selection.resetNodeColor(geometryNode)
            sendCacheSelectionUpdate()
            if selection.selectedNodes.contains(nameNode) {
                selection.selectedNodes.remove(nameNode)
                sendSelectionUpdate()
            }
            return
        }

        // Toggle selection
        if selection.selectedNodes.contains(nameNode) {
            selection.selectedNodes.remove(nameNode)
            selection.resetNodeColor(geometryNode)
        } else {
            selection.selectedNodes.insert(nameNode)
            selection.applyHighlight(to: geometryNode, forNodeName: nameNode.name)
            if selection.enableCache {
                selection.cacheManager?.addToCache(nodeName)
            }
        }

        sendSelectionUpdate()
    }

    // MARK: - Preselection

    private func applyPreselectedEntities() {
        guard let names = pendingPreselectedEntities, !names.isEmpty else { return }

        scnView.scene?.rootNode.enumerateChildNodes { (node, _) in
            if let nodeName = node.name, names.contains(nodeName),
               let geometryNode = self.selection.findGeometryNode(in: node) {
                self.selection.selectedNodes.insert(node)
                self.selection.applyHighlight(to: geometryNode, forNodeName: nodeName)
            }
        }
        sendSelectionUpdate()
        pendingPreselectedEntities = nil
    }

    // MARK: - Events

    private func sendSelectionUpdate() {
        guard let eventSink = eventSink else { return }
        let entities = selection.selectedNodes.map { node in
            ["id": node.hash, "name": node.name ?? "Unnamed"] as [String: Any]
        }
        eventSink(["event": "selectionChanged", "selectedEntities": entities])
    }

    private func sendCacheSelectionUpdate() {
        guard let eventSink = eventSink,
              selection.enableCache,
              let cacheMgr = selection.cacheManager else { return }
        let cached = cacheMgr.cachedEntities.map { ["name": $0] }
        eventSink(["event": "cacheSelectionChanged", "cachedEntities": cached])
    }

    // MARK: - Cleanup

    deinit {
        cleanup()
    }

    func dispose() {
        cleanup()
    }

    private func cleanup() {
        guard !isDisposed else { return }
        isDisposed = true

        // Break retain cycles
        methodChannel.setMethodCallHandler(nil)
        eventChannel.setStreamHandler(nil)
        eventSink = nil

        // Remove gesture recognizers
        scnView.gestureRecognizers?.forEach { scnView.removeGestureRecognizer($0) }

        // Stop rendering
        scnView.isPlaying = false
        scnView.stop(nil)

        // Clean up managers
        selection.cleanup()
        sequenceValidator.reset()
        sceneManager.cleanup()

        pendingPreselectedEntities = nil
    }
}
