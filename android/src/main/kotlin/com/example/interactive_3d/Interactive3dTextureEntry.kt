package com.example.interactive_3d

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import com.example.interactive_3d.renderer.FilamentRenderer
import java.nio.ByteBuffer

/**
 * Bridges Flutter's SurfaceProducer with the Filament renderer.
 *
 * Creates the [FilamentRenderer] once the surface is valid, either at
 * startup or on the first load that needs it, and answers each model load
 * only after it has actually finished.
 */
class Interactive3dTextureEntry(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val messenger: BinaryMessenger,
    private val width: Int,
    private val height: Int
) : TextureRegistry.SurfaceProducer.Callback {

    private companion object {
        const val TAG = "Interactive3dTexture"
    }

    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
    private var filamentRenderer: FilamentRenderer? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    // Answered exactly once: by the load itself, a newer load, or dispose.
    private var pendingLoadResult: MethodChannel.Result? = null

    private var currentWidth: Int = width
    private var currentHeight: Int = height

    /**
     * Creates the SurfaceProducer and returns the texture ID used by
     * Flutter's [Texture] widget. Returns -1 on failure.
     */
    fun initialize(): Long {
        try {
            surfaceProducer = textureRegistry.createSurfaceProducer()
            val producer = surfaceProducer ?: return -1L

            producer.setSize(width, height)
            // Below API 29, release() throws if the surface was never requested.
            producer.getSurface()
            producer.setCallback(this)

            val textureId = producer.id()

            eventChannel = EventChannel(messenger, "interactive_3d_events_$textureId")
            eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

            mainHandler.post { initializeRendererIfReady() }
            return textureId
        } catch (e: Exception) {
            Log.e(TAG, "Initialization failed: ${e.message}", e)
            runCatching { surfaceProducer?.release() }
            surfaceProducer = null
            return -1L
        }
    }

    override fun onSurfaceAvailable() {
        mainHandler.post { initializeRendererIfReady() }
    }

    override fun onSurfaceCleanup() {
        mainHandler.post { filamentRenderer?.destroySwapChain() }
    }

    private fun initializeRendererIfReady() {
        val producer = surfaceProducer ?: return
        val surface = producer.getSurface()
        if (!surface.isValid) return

        if (filamentRenderer == null) {
            filamentRenderer = FilamentRenderer(context, currentWidth, currentHeight)
            filamentRenderer?.setSelectionListener { sendSelectionEvent(it) }
            filamentRenderer?.setCacheSelectionListener { sendCacheSelectionEvent(it) }
            filamentRenderer?.setSelectionRejectedListener { sendSelectionRejectedEvent(it) }
        }

        filamentRenderer?.createSwapChain(producer.getSurface())
        filamentRenderer?.startRenderLoop()
    }

    // -- Delegated operations -------------------------------------------------

    fun updateSize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        currentWidth = width
        currentHeight = height
        surfaceProducer?.setSize(width, height)
        filamentRenderer?.updateViewport(width, height)
    }

    fun loadModel(
        buffer: ByteBuffer, fileName: String, resources: Map<String, ByteArray>,
        preselectedEntities: List<String>?, selectionColor: List<Double>?,
        patchColors: List<Map<String, Any>>?, enableCache: Boolean, cacheColor: List<Double>?,
        clearSelectionsOnHighlight: Boolean = false,
        selectionSequence: List<Map<String, Any>>? = null,
        initialMaterialOverrides: List<Map<String, Any>>? = null,
        initialEntityTextures: List<Map<String, Any>>? = null,
        backgroundColor: List<Double>? = null,
        result: MethodChannel.Result
    ) {
        replyLoad { it.error("LOAD_SUPERSEDED", "A newer model load replaced this one", null) }
        pendingLoadResult = result

        mainHandler.post {
            try {
                val renderer = ensureRenderer()
                    ?: return@post replyLoad {
                        it.error("RENDERER_UNAVAILABLE", "Rendering surface is not ready", null)
                    }
                if (backgroundColor != null) renderer.setBackgroundColor(backgroundColor)
                val loaded = renderer.loadModel(
                    buffer, fileName, resources, preselectedEntities,
                    selectionColor, patchColors, enableCache, cacheColor,
                    clearSelectionsOnHighlight, selectionSequence,
                    initialMaterialOverrides, initialEntityTextures
                )
                replyLoad {
                    if (loaded) it.success(null)
                    else it.error("MODEL_LOAD_FAILED", "Could not load $fileName", null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error loading model: ${e.message}", e)
                replyLoad { it.error("MODEL_LOAD_FAILED", e.message, null) }
            }
        }
    }

    fun loadEnvironment(iblBuffer: ByteBuffer, skyboxBuffer: ByteBuffer) =
        mainHandler.post {
            try {
                val renderer = ensureRenderer()
                if (renderer == null) {
                    Log.w(TAG, "Environment skipped: renderer not ready")
                    return@post
                }
                renderer.loadEnvironment(iblBuffer, skyboxBuffer)
            } catch (e: Exception) {
                Log.e(TAG, "Error loading environment: ${e.message}", e)
            }
        }

    private fun ensureRenderer(): FilamentRenderer? {
        if (filamentRenderer == null) initializeRendererIfReady()
        return filamentRenderer
    }

    private fun replyLoad(reply: (MethodChannel.Result) -> Unit) {
        val result = pendingLoadResult ?: return
        pendingLoadResult = null
        reply(result)
    }

    fun setCameraZoomLevel(zoom: Float) =
        mainHandler.post { filamentRenderer?.setCameraZoomLevel(zoom) }

    fun resetCamera(zoom: Float) =
        mainHandler.post { filamentRenderer?.resetCamera(zoom) }

    fun zoomBy(delta: Float) =
        mainHandler.post { filamentRenderer?.zoomBy(delta) }

    fun setPartGroupVisibility(group: Map<String, Any>, isVisible: Boolean) =
        mainHandler.post { filamentRenderer?.setPartGroupVisibility(group, isVisible) }

    fun unselectEntities(entityIds: List<Long>?) =
        mainHandler.post { filamentRenderer?.unselectEntities(entityIds) }

    fun clearCache() =
        mainHandler.post { filamentRenderer?.clearCacheAndRestoreSelections() }

    fun refreshCacheHighlights() =
        mainHandler.post { filamentRenderer?.refreshCacheHighlights() }

    fun removeFromCache(names: List<String>) =
        mainHandler.post { filamentRenderer?.removeFromCache(names) }

    fun setEntityMaterials(overrides: List<Map<String, Any>>) =
        mainHandler.post { filamentRenderer?.setEntityMaterials(overrides) }

    fun resetEntityMaterials(names: List<String>?) =
        mainHandler.post { filamentRenderer?.resetEntityMaterials(names) }

    fun setEntityTextures(textures: List<Map<String, Any>>) =
        mainHandler.post { filamentRenderer?.setEntityTextures(textures) }

    fun resetEntityTextures(names: List<String>?) =
        mainHandler.post { filamentRenderer?.resetEntityTextures(names) }

    fun onTap(x: Float, y: Float) =
        mainHandler.post { filamentRenderer?.onTap(x.toInt(), y.toInt()) }

    fun onPan(deltaX: Float, deltaY: Float) =
        mainHandler.post { filamentRenderer?.onPan(deltaX, deltaY) }

    fun onScale(scale: Float) =
        mainHandler.post { filamentRenderer?.onScale(scale) }

    // -- Events ---------------------------------------------------------------

    private fun sendSelectionEvent(entities: List<Map<String, Any>>) {
        mainHandler.post {
            eventSink?.success(mapOf("event" to "selectionChanged", "selectedEntities" to entities))
        }
    }

    private fun sendCacheSelectionEvent(entities: List<Map<String, Any>>) {
        mainHandler.post {
            eventSink?.success(mapOf("event" to "cacheSelectionChanged", "cachedEntities" to entities))
        }
    }

    private fun sendSelectionRejectedEvent(name: String) {
        mainHandler.post {
            eventSink?.success(mapOf("event" to "selectionRejected", "name" to name))
        }
    }

    // -- Cleanup --------------------------------------------------------------

    fun dispose() {
        eventSink = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null

        mainHandler.removeCallbacksAndMessages(null)
        replyLoad { it.error("DISPOSED", "The 3D view was disposed before loading finished", null) }

        filamentRenderer?.cleanup()
        filamentRenderer = null

        surfaceProducer?.setCallback(null)
        surfaceProducer?.release()
        surfaceProducer = null
    }
}