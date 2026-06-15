package com.bowvie.flutter_native_ai

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** FlutterNativeAiPlugin */
class FlutterNativeAiPlugin : FlutterPlugin {
    private var bridge: OnDeviceAiBridge? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = flutterPluginBinding.binaryMessenger
        bridge = OnDeviceAiBridge().also {
            OnDeviceAiHostApi.setUp(messenger, it)
            it.registerStreamHandler(messenger)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        OnDeviceAiHostApi.setUp(binding.binaryMessenger, null)
        bridge?.close()
        bridge = null
    }
}
