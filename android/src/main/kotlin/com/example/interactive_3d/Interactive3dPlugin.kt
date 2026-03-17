package com.example.interactive_3d

import android.content.Context
import android.util.Log
import com.google.android.filament.utils.Utils
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap

/**
 * Flutter plugin entry point for interactive_3d.
 *
 * Receives method calls from Dart, creates and manages [Interactive3dTextureEntry]
 * instances per texture ID, and routes all operations to the correct entry.
 */
class Interactive3dPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

  private companion object {
    const val TAG = "Interactive3dPlugin"
    const val METHOD_CHANNEL = "interactive_3d_plugin"

    init {
      Utils.init()
    }
  }

  private lateinit var methodChannel: MethodChannel
  private lateinit var textureRegistry: TextureRegistry
  private lateinit var messenger: BinaryMessenger
  private lateinit var context: Context

  private val textureEntries = ConcurrentHashMap<Long, Interactive3dTextureEntry>()

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    messenger = binding.binaryMessenger
    textureRegistry = binding.textureRegistry

    methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    methodChannel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    textureEntries.values.forEach { entry ->
      try { entry.dispose() }
      catch (e: Exception) { Log.e(TAG, "Error disposing entry: ${e.message}") }
    }
    textureEntries.clear()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "createTexture" -> handleCreateTexture(call, result)
      "disposeTexture" -> handleDisposeTexture(call, result)
      "loadModel" -> handleLoadModel(call, result)
      "loadEnvironment" -> handleLoadEnvironment(call, result)
      "setZoomLevel" -> handleSetZoomLevel(call, result)
      "setPartGroupVisibility" -> handleSetPartGroupVisibility(call, result)
      "unselectEntities" -> handleUnselectEntities(call, result)
      "clearCache" -> handleClearCache(call, result)
      "refreshCacheHighlights" -> handleRefreshCacheHighlights(call, result)
      "removeFromCache" -> handleRemoveFromCache(call, result)
      "onTouchEvent" -> handleTouchEvent(call, result)
      else -> result.notImplemented()
    }
  }

  // -------------------------------------------------------------------------
  // Texture lifecycle
  // -------------------------------------------------------------------------

  private fun handleCreateTexture(call: MethodCall, result: MethodChannel.Result) {
    val width = call.argument<Int>("width") ?: 800
    val height = call.argument<Int>("height") ?: 600

    try {
      val entry = Interactive3dTextureEntry(context, textureRegistry, messenger, width, height)
      val textureId = entry.initialize()

      if (textureId != -1L) {
        textureEntries[textureId] = entry
        result.success(mapOf("textureId" to textureId))
      } else {
        result.error("TEXTURE_CREATION_FAILED", "Failed to create SurfaceProducer", null)
      }
    } catch (e: Exception) {
      Log.e(TAG, "Error creating texture: ${e.message}", e)
      result.error("TEXTURE_CREATION_FAILED", e.message, null)
    }
  }

  private fun handleDisposeTexture(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error("INVALID_ARGUMENT", "textureId required", null)

    textureEntries.remove(textureId)?.let {
      it.dispose()
      result.success(null)
    } ?: result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)
  }

  // -------------------------------------------------------------------------
  // Model & Environment
  // -------------------------------------------------------------------------

  private fun handleLoadModel(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val modelBytes = call.argument<ByteArray>("modelBytes")
    val modelName = call.argument<String>("name")

    if (textureId == null || modelBytes == null || modelName == null) {
      return result.error("INVALID_ARGUMENT", "textureId, modelBytes and name required", null)
    }

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    try {
      val backgroundColor = call.argument<List<Double>>("backgroundColor")
      if (backgroundColor != null && backgroundColor.size >= 3) {
        entry.setBackgroundColor(backgroundColor)
      }

      entry.loadModel(
        buffer = ByteBuffer.wrap(modelBytes),
        fileName = modelName,
        resources = call.argument<Map<String, ByteArray>>("resources") ?: emptyMap(),
        preselectedEntities = call.argument("preselectedEntities"),
        selectionColor = call.argument("selectionColor"),
        patchColors = call.argument("patchColors"),
        enableCache = call.argument<Boolean>("enableCache") ?: false,
        cacheColor = call.argument("cacheColor"),
        clearSelectionsOnHighlight = call.argument<Boolean>("clearSelectionsOnHighlight") ?: false
      )
      result.success(null)
    } catch (e: Exception) {
      Log.e(TAG, "Error loading model: ${e.message}", e)
      result.error("MODEL_LOAD_FAILED", e.message, null)
    }
  }

  private fun handleLoadEnvironment(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error("INVALID_ARGUMENT", "textureId required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    val iblBytes = call.argument<ByteArray>("iblBytes")
    val skyboxBytes = call.argument<ByteArray>("skyboxBytes")

    if (iblBytes != null && skyboxBytes != null) {
      try {
        entry.loadEnvironment(ByteBuffer.wrap(iblBytes), ByteBuffer.wrap(skyboxBytes))
      } catch (e: Exception) {
        Log.e(TAG, "Error loading environment: ${e.message}", e)
        return result.error("ENVIRONMENT_LOAD_FAILED", e.message, null)
      }
    }
    result.success(null)
  }

  // -------------------------------------------------------------------------
  // Camera
  // -------------------------------------------------------------------------

  private fun handleSetZoomLevel(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val zoom = call.argument<Double>("zoom")?.toFloat()

    if (textureId == null || zoom == null)
      return result.error("INVALID_ARGUMENT", "textureId and zoom required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.setCameraZoomLevel(zoom)
    result.success(null)
  }

  // -------------------------------------------------------------------------
  // Visibility
  // -------------------------------------------------------------------------

  private fun handleSetPartGroupVisibility(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val group = call.argument<Map<String, Any>>("group")
    val visibility = call.argument<Map<String, Boolean>>("visibility")

    if (textureId == null || group == null || visibility == null)
      return result.error("INVALID_ARGUMENT", "textureId, group, and visibility required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    val title = group["title"] as? String
    val isVisible = visibility[title]

    if (title != null && isVisible != null) {
      entry.setPartGroupVisibility(group, isVisible)
    }
    result.success(null)
  }

  // -------------------------------------------------------------------------
  // Selection & Cache
  // -------------------------------------------------------------------------

  private fun handleUnselectEntities(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error("INVALID_ARGUMENT", "textureId required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.unselectEntities(call.argument("entityIds"))
    result.success(null)
  }

  private fun handleClearCache(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error("INVALID_ARGUMENT", "textureId required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.clearCache()
    result.success(null)
  }

  private fun handleRefreshCacheHighlights(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
      ?: return result.error("INVALID_ARGUMENT", "textureId required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.refreshCacheHighlights()
    result.success(null)
  }

  private fun handleRemoveFromCache(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val names = call.argument<List<String>>("names")

    if (textureId == null || names == null)
      return result.error("INVALID_ARGUMENT", "textureId and names required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    entry.removeFromCache(names)
    result.success(null)
  }

  // -------------------------------------------------------------------------
  // Touch events
  // -------------------------------------------------------------------------

  private fun handleTouchEvent(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val action = call.argument<String>("action")

    if (textureId == null || action == null)
      return result.error("INVALID_ARGUMENT", "textureId and action required", null)

    val entry = textureEntries[textureId]
      ?: return result.error("TEXTURE_NOT_FOUND", "Texture $textureId not found", null)

    when (action) {
      "tap" -> {
        val x = call.argument<Double>("x")?.toFloat()
        val y = call.argument<Double>("y")?.toFloat()
        if (x != null && y != null) entry.onTap(x, y)
      }
      "pan" -> {
        val dx = call.argument<Double>("deltaX")?.toFloat()
        val dy = call.argument<Double>("deltaY")?.toFloat()
        if (dx != null && dy != null) entry.onPan(dx, dy)
      }
      "scale" -> {
        val s = call.argument<Double>("scale")?.toFloat()
        if (s != null) entry.onScale(s)
      }
    }
    result.success(null)
  }
}