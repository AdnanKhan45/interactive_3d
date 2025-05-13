import Flutter
import UIKit

public class Interactive3DPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = Interactive3DViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "interactive_3d")
    }
}