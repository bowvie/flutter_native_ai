import Flutter

public class FlutterOnDeviceAiPlugin: NSObject, FlutterPlugin {
  private let bridge = OnDeviceAiBridge()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterOnDeviceAiPlugin()
    OnDeviceAiHostApiSetup.setUp(
      binaryMessenger: registrar.messenger(),
      api: instance.bridge
    )
    instance.bridge.registerStreamHandler(with: registrar.messenger())
  }
}
