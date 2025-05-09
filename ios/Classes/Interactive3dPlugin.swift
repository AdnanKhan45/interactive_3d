import Flutter
import UIKit

public class Interactive3DPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = Interactive3DViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "interactive_3d")
    }
}

class Interactive3DViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return Interactive3DPlatformView(frame: frame, viewId: viewId, messenger: messenger, args: args)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

class Interactive3DPlatformView: NSObject, FlutterPlatformView, FlutterStreamHandler {
    private let filamentRenderer: FILRenderer
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, args: Any?) {
        filamentRenderer = FILRenderer(frame: frame)
        methodChannel = FlutterMethodChannel(name: "interactive_3d_\(viewId)", binaryMessenger: messenger)
        eventChannel = FlutterEventChannel(name: "interactive_3d_events_\(viewId)", binaryMessenger: messenger)

        super.init()

        methodChannel.setMethodCallHandler(handleMethodCall)
        eventChannel.setStreamHandler(self)

        if let params = args as? [String: Any] {
            filamentRenderer.creationParams = params
        }

        filamentRenderer.selectionCallback = { [weak self] selectedEntities in
            let event = [
                "event": "selectionChanged",
                "selectedEntities": selectedEntities.map { entity in
                    var selected: SelectedEntity = SelectedEntity()
                    entity.getValue(&selected)
                    return ["id": selected.id, "name": selected.name ?? ""]
                }
            ]
            DispatchQueue.main.async {
                self?.eventSink?(event)
            }
        }
    }

    func view() -> UIView {
        return filamentRenderer
    }

    func dispose() {
        filamentRenderer.destroyModel()
    }

    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            guard let args = call.arguments as? [String: Any],
                  let modelBytes = (args["modelBytes"] as? FlutterStandardTypedData)?.data,
                  let modelName = args["name"] as? String,
                  let resources = args["resources"] as? [String: FlutterStandardTypedData],
                  let preselectedEntities = args["preselectedEntities"] as? [String]?,
                  let selectionColor = args["selectionColor"] as? [Double]? else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments for loadModel", details: nil))
                return
            }

            let resourceMap = resources.mapValues { $0.data }
            var patchColors: [PatchColor]? = nil
            if let patchColorsData = args["patchColors"] as? [[String: Any]] {
                patchColors = patchColorsData.map { patch in
                    let name = patch["name"] as? String ?? ""
                    let color = (patch["color"] as? [Double])?.map { Float($0) } ?? [0.0, 1.0, 0.0, 1.0]
                    return PatchColor(name: name, color: color)
                }
            }

            DispatchQueue.main.async { [weak self] in
                self?.filamentRenderer.loadModel(
                    modelBytes: modelBytes,
                    modelName: modelName,
                    resources: resourceMap,
                    preselectedEntities: preselectedEntities,
                    selectionColor: selectionColor?.map { NSNumber(value: $0) },
                    patchColors: patchColors
                )
                result(nil)
            }

        case "loadEnvironment":
            guard let args = call.arguments as? [String: Any],
                  let iblBytes = (args["iblBytes"] as? FlutterStandardTypedData)?.data,
                  let skyboxBytes = (args["skyboxBytes"] as? FlutterStandardTypedData)?.data else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments for loadEnvironment", details: nil))
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.filamentRenderer.loadEnvironment(iblBytes: iblBytes, skyboxBytes: skyboxBytes)
                result(nil)
            }

        case "setZoomLevel":
            guard let args = call.arguments as? [String: Any],
                  let zoom = args["zoom"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid zoom value", details: nil))
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.filamentRenderer.setCameraZoomLevel(Float(zoom))
                result(nil)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}