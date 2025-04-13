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
        return Interactive3DPlatformView(frame: frame, viewId: viewId, messenger: messenger)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

class Interactive3DPlatformView: NSObject, FlutterPlatformView, FlutterStreamHandler {
    // Filament renderer (actual native implementation, not a custom view)
    private let filamentRenderer: FILRenderer

    // Channels for communication
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        // Initialize the Filament renderer
        filamentRenderer = FILRenderer(frame: frame)

        // Initialize method and event channels
        methodChannel = FlutterMethodChannel(name: "interactive_3d_\(viewId)", binaryMessenger: messenger)
        eventChannel = FlutterEventChannel(name: "interactive_3d_events_\(viewId)", binaryMessenger: messenger)

        super.init()

        // Set handlers for method and event channels
        methodChannel.setMethodCallHandler(handleMethodCall)
        eventChannel.setStreamHandler(self)
    }

    func view() -> UIView {
        return filamentRenderer
    }

    func dispose() {
        filamentRenderer.destroyModel()
    }

    // Handle method calls from Flutter
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            guard let args = call.arguments as? [String: Any],
                  let modelBytes = (args["modelBytes"] as? FlutterStandardTypedData)?.data,
                  let modelName = args["name"] as? String,
                  let resources = args["resources"] as? [String: FlutterStandardTypedData] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments for loadModel", details: nil))
                return
            }


            // Determine if it's a .gltf or .glb file
            if modelName.lowercased().hasSuffix(".gltf") {
                // Load the model into Filament
                filamentRenderer.loadModelGltf(modelBytes) { resourceName in
                    guard let resourceName = resourceName else {
                        return Data() // Return empty data if resourceName is nil
                    }
                    return resources[resourceName]?.data ?? Data()
                }

                print("Loaded GLTF model: \(modelName)")
            } else if modelName.lowercased().hasSuffix(".glb") {
                filamentRenderer.loadModelGlb(modelBytes)
                print("Loaded GLB model: \(modelName)")
            } else {
                print("Unsupported model format: \(modelName)")
                result(FlutterError(code: "UNSUPPORTED_FORMAT", message: "Only .gltf and .glb formats are supported", details: nil))
                return
            }



            result(nil)

        case "loadEnvironment":
            guard let args = call.arguments as? [String: Any],
                  let iblBytes = (args["iblBytes"] as? FlutterStandardTypedData)?.data,
                  let skyboxBytes = (args["skyboxBytes"] as? FlutterStandardTypedData)?.data else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments for loadEnvironment", details: nil))
                return
            }

            // Load the environment textures
            filamentRenderer.loadEnvironment(iblBytes, skybox: skyboxBytes)
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // Handle events for EventChannel
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
