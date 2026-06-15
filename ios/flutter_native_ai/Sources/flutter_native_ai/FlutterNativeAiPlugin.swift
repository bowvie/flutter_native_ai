import Flutter

public class FlutterNativeAiPlugin: NSObject, FlutterPlugin {
  private let bridge = OnDeviceAiBridge()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterNativeAiPlugin()
    OnDeviceAiHostApiSetup.setUp(
      binaryMessenger: registrar.messenger(),
      api: instance.bridge
    )
    instance.bridge.registerStreamHandler(with: registrar.messenger())
  }
}
