import Flutter
import UIKit

public class Interactive3dPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = Interactive3dViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "interactive_3d")
    }
}