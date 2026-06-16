#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

public class FlutterNativeAiPlugin: NSObject, FlutterPlugin {
  private let bridge = OnDeviceAiBridge()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterNativeAiPlugin()
    #if os(iOS)
      let messenger = registrar.messenger()
    #elseif os(macOS)
      let messenger = registrar.messenger
    #endif

    OnDeviceAiHostApiSetup.setUp(
      binaryMessenger: messenger,
      api: instance.bridge
    )
    instance.bridge.registerStreamHandler(with: messenger)
  }
}
