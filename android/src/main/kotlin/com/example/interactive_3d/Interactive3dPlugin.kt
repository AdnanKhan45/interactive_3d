package com.example.interactive_3d

import android.content.Context
import android.util.Log
import com.google.android.filament.utils.Utils
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap

/**
 * Interactive3dPlugin - Flutter plugin for rendering 3D models using Filament.
 *
 * This implementation uses Flutter's SurfaceProducer API for high-performance
 * texture-based rendering instead of PlatformView, avoiding the performance
 * overhead associated with AndroidView/Hybrid Composition.
 */
class Interactive3dPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

  companion object {
    private const val TAG = "Interactive3dPlugin"
    private const val METHOD_CHANNEL = "interactive_3d_plugin"

    init {
      // Initialize Filament native libraries
      Utils.init()
      Log.d(TAG, "Filament initialized via Utils.init()")
    }
  }

  private lateinit var methodChannel: MethodChannel
  private lateinit var textureRegistry: TextureRegistry
  private lateinit var messenger: BinaryMessenger
  private lateinit var context: Context

  // Store active texture entries by their ID
  private val textureEntries = ConcurrentHashMap<Long, Interactive3dTextureEntry>()

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    Log.d(TAG, "onAttachedToEngine")

    context = flutterPluginBinding.applicationContext
    messenger = flutterPluginBinding.binaryMessenger
    textureRegistry = flutterPluginBinding.textureRegistry

    methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    methodChannel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    Log.d(TAG, "onDetachedFromEngine - cleaning up ${textureEntries.size} texture entries")

    methodChannel.setMethodCallHandler(null)

    // Cleanup all texture entries
    textureEntries.values.forEach { entry ->
      try {
        entry.dispose()
      } catch (e: Exception) {
        Log.e(TAG, "Error disposing texture entry: ${e.message}")
      }
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
      "onTouchEvent" -> handleTouchEvent(call, result)
      else -> result.notImplemented()
    }
  }

  /**
   * Creates a new texture entry for 3D rendering.
   * Returns the texture ID to be used with Flutter's Texture widget.
   */
  private fun handleCreateTexture(call: MethodCall, result: MethodChannel.Result) {
    val width = call.argument<Int>("width") ?: 800
    val height = call.argument<Int>("height") ?: 600

    try {
      val textureEntry = Interactive3dTextureEntry(
        context = context,
        textureRegistry = textureRegistry,
        messenger = messenger,
        width = width,
        height = height
      )

      val textureId = textureEntry.initialize()
      if (textureId != -1L) {
        textureEntries[textureId] = textureEntry
        Log.d(TAG, "Created texture with ID: $textureId (${width}x${height})")
        result.success(mapOf("textureId" to textureId))
      } else {
        result.error("TEXTURE_CREATION_FAILED", "Failed to create SurfaceProducer", null)
      }
    } catch (e: Exception) {
      Log.e(TAG, "Error creating texture: ${e.message}", e)
      result.error("TEXTURE_CREATION_FAILED", e.message, null)
    }
  }

  /**
   * Disposes a texture entry and releases all associated resources.
   */
  private fun handleDisposeTexture(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    if (textureId == null) {
      result.error("INVALID_ARGUMENT", "textureId is required", null)
      return
    }

    val entry = textureEntries.remove(textureId)
    if (entry != null) {
      entry.dispose()
      Log.d(TAG, "Disposed texture with ID: $textureId")
      result.success(null)
    } else {
      result.error("TEXTURE_NOT_FOUND", "Texture with ID $textureId not found", null)
    }
  }

  /**
   * Loads a 3D model into the specified texture entry.
   */
  private fun handleLoadModel(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val modelBytes = call.argument<ByteArray>("modelBytes")
    val modelName = call.argument<String>("name")
    val resources = call.argument<Map<String, ByteArray>>("resources") ?: emptyMap()
    val preselectedEntities = call.argument<List<String>?>("preselectedEntities")
    val selectionColor = call.argument<List<Double>?>("selectionColor")
    val patchColors = call.argument<List<Map<String, Any>>>("patchColors")
    val enableCache = call.argument<Boolean>("enableCache") ?: false
    val cacheColor = call.argument<List<Double>?>("cacheColor")

    if (textureId == null || modelBytes == null || modelName == null) {
      result.error("INVALID_ARGUMENT", "textureId, modelBytes and name are required", null)
      return
    }

    val entry = textureEntries[textureId]
    if (entry == null) {
      result.error("TEXTURE_NOT_FOUND", "Texture with ID $textureId not found", null)
      return
    }

    try {
      entry.loadModel(
        buffer = ByteBuffer.wrap(modelBytes),
        fileName = modelName,
        resources = resources,
        preselectedEntities = preselectedEntities,
        selectionColor = selectionColor,
        patchColors = patchColors,
        enableCache = enableCache,
        cacheColor = cacheColor
      )
      result.success(null)
    } catch (e: Exception) {
      Log.e(TAG, "Error loading model: ${e.message}", e)
      result.error("MODEL_LOAD_FAILED", e.message, null)
    }
  }

  /**
   * Loads environment lighting (IBL + Skybox) into the specified texture entry.
   */
  private fun handleLoadEnvironment(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val iblBytes = call.argument<ByteArray>("iblBytes")
    val skyboxBytes = call.argument<ByteArray>("skyboxBytes")

    if (textureId == null) {
      result.error("INVALID_ARGUMENT", "textureId is required", null)
      return
    }

    val entry = textureEntries[textureId]
    if (entry == null) {
      result.error("TEXTURE_NOT_FOUND", "Texture with ID $textureId not found", null)
      return
    }

    try {
      if (iblBytes != null && skyboxBytes != null) {
        entry.loadEnvironment(
          iblBuffer = ByteBuffer.wrap(iblBytes),
          skyboxBuffer = ByteBuffer.wrap(skyboxBytes)
        )
      }
      result.success(null)
    } catch (e: Exception) {
      Log.e(TAG, "Error loading environment: ${e.message}", e)
      result.error("ENVIRONMENT_LOAD_FAILED", e.message, null)
    }
  }

  /**
   * Sets the camera zoom level.
   */
  private fun handleSetZoomLevel(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val zoom = call.argument<Double>("zoom")?.toFloat()

    if (textureId == null || zoom == null) {
      result.error("INVALID_ARGUMENT", "textureId and zoom are required", null)
      return
    }

    val entry = textureEntries[textureId]
    if (entry == null) {
      result.error("TEXTURE_NOT_FOUND", "Texture with ID $textureId not found", null)
      return
    }

    entry.setCameraZoomLevel(zoom)
    result.success(null)
  }

  /**
   * Sets visibility for a group of model parts.
   */
  private fun handleSetPartGroupVisibility(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val group = call.argument<Map<String, Any>>("group")
    val visibility = call.argument<Map<String, Boolean>>("visibility")

    if (textureId == null || group == null || visibility == null) {
      result.error("INVALID_ARGUMENT", "textureId, group, and visibility are required", null)
      return
    }

    val entry = textureEntries[textureId]
    if (entry == null) {
      result.error("TEXTURE_NOT_FOUND", "Texture with ID $textureId not found", null)
      return
    }

    val title = group["title"] as? String
    val isVisible = visibility[title] as? Boolean

    if (title != null && isVisible != null) {
      entry.setPartGroupVisibility(group, isVisible)
    }
    result.success(null)
  }

  /**
   * Unselects entities in the 3D model.
   */
  private fun handleUnselectEntities(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val entityIds = call.argument<List<Long>?>("entityIds")

    if (textureId == null) {
      result.error("INVALID_ARGUMENT", "textureId is required", null)
      return
    }

    val entry = textureEntries[textureId]
    if (entry == null) {
      result.error("TEXTURE_NOT_FOUND", "Texture with ID $textureId not found", null)
      return
    }

    entry.unselectEntities(entityIds)
    result.success(null)
  }

  /**
   * Clears the selection cache.
   */
  private fun handleClearCache(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()

    if (textureId == null) {
      result.error("INVALID_ARGUMENT", "textureId is required", null)
      return
    }

    val entry = textureEntries[textureId]
    if (entry == null) {
      result.error("TEXTURE_NOT_FOUND", "Texture with ID $textureId not found", null)
      return
    }

    entry.clearCache()
    result.success(null)
  }

  /**
   * Handles touch events forwarded from Flutter.
   */
  private fun handleTouchEvent(call: MethodCall, result: MethodChannel.Result) {
    val textureId = call.argument<Number>("textureId")?.toLong()
    val action = call.argument<String>("action")
    val x = call.argument<Double>("x")?.toFloat()
    val y = call.argument<Double>("y")?.toFloat()
    val deltaX = call.argument<Double>("deltaX")?.toFloat()
    val deltaY = call.argument<Double>("deltaY")?.toFloat()
    val scale = call.argument<Double>("scale")?.toFloat()

    if (textureId == null || action == null) {
      result.error("INVALID_ARGUMENT", "textureId and action are required", null)
      return
    }

    val entry = textureEntries[textureId]
    if (entry == null) {
      result.error("TEXTURE_NOT_FOUND", "Texture with ID $textureId not found", null)
      return
    }

    when (action) {
      "tap" -> {
        if (x != null && y != null) {
          entry.onTap(x, y)
        }
      }
      "pan" -> {
        if (deltaX != null && deltaY != null) {
          entry.onPan(deltaX, deltaY)
        }
      }
      "scale" -> {
        if (scale != null) {
          entry.onScale(scale)
        }
      }
    }
    result.success(null)
  }
}