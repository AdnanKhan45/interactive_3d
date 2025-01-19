
// Interactive3dPlugin.kt

package com.example.interactive_3d

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger

class Interactive3dPlugin: FlutterPlugin {
  private lateinit var factory: Interactive3dFactory

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    val messenger: BinaryMessenger = flutterPluginBinding.binaryMessenger
    factory = Interactive3dFactory(messenger)
    flutterPluginBinding.platformViewRegistry.registerViewFactory("interactive_3d", factory)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
