import Flutter

/// Breaks the retain cycle between FlutterEventChannel and its stream handler.
///
/// FlutterEventChannel holds its stream handler strongly. If the handler is
/// the platform view itself, the view can never be deallocated. This wrapper
/// holds a weak reference instead, allowing normal deallocation.
class WeakStreamHandler: NSObject, FlutterStreamHandler {
    weak var delegate: (FlutterStreamHandler & AnyObject)?

    init(delegate: FlutterStreamHandler & AnyObject) {
        self.delegate = delegate
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        return delegate?.onListen(withArguments: arguments, eventSink: events)
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return delegate?.onCancel(withArguments: arguments)
    }
}
