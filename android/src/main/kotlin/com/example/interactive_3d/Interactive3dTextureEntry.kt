package com.example.interactive_3d

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry
import com.example.interactive_3d.renderer.FilamentRenderer
import java.nio.ByteBuffer

/**
 * Bridges Flutter's SurfaceProducer with the Filament renderer.
 *
 * Manages the surface lifecycle: creates a [FilamentRenderer] when the
 * surface first becomes available, destroys and recreates the SwapChain
 * on app background/resume, and queues model/environment loads that
 * arrive before the surface is ready.
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

    // Operations queued before the surface is available
    private var pendingModelLoad: (() -> Unit)? = null
    private var pendingEnvironmentLoad: (() -> Unit)? = null

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
            return -1L
        }
    }

    override fun onSurfaceAvailable() {
        mainHandler.post {
            initializeRendererIfReady()
            pendingModelLoad?.invoke()
            pendingModelLoad = null
            pendingEnvironmentLoad?.invoke()
            pendingEnvironmentLoad = null
        }
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
        clearSelectionsOnHighlight: Boolean = false
    ) {
        val op = {
            filamentRenderer?.loadModel(
                buffer, fileName, resources, preselectedEntities,
                selectionColor, patchColors, enableCache, cacheColor,
                clearSelectionsOnHighlight
            )
        }
        if (filamentRenderer != null && surfaceProducer?.getSurface()?.isValid == true) {
            mainHandler.post { op() }
        } else {
            pendingModelLoad = { op(); Unit }
        }
    }

    fun loadEnvironment(iblBuffer: ByteBuffer, skyboxBuffer: ByteBuffer) {
        val op = { filamentRenderer?.loadEnvironment(iblBuffer, skyboxBuffer) }
        if (filamentRenderer != null && surfaceProducer?.getSurface()?.isValid == true) {
            mainHandler.post { op() }
        } else {
            pendingEnvironmentLoad = { op(); Unit }
        }
    }

    fun setCameraZoomLevel(zoom: Float) =
        mainHandler.post { filamentRenderer?.setCameraZoomLevel(zoom) }

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

    fun onTap(x: Float, y: Float) =
        mainHandler.post { filamentRenderer?.onTap(x.toInt(), y.toInt()) }

    fun onPan(deltaX: Float, deltaY: Float) =
        mainHandler.post { filamentRenderer?.onPan(deltaX, deltaY) }

    fun onScale(scale: Float) =
        mainHandler.post { filamentRenderer?.onScale(scale) }

    fun setBackgroundColor(color: List<Double>) {
        filamentRenderer?.setBackgroundColor(color)
    }

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

    // -- Cleanup --------------------------------------------------------------

    fun dispose() {
        eventSink = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null

        mainHandler.removeCallbacksAndMessages(null)

        filamentRenderer?.cleanup()
        filamentRenderer = null

        surfaceProducer?.setCallback(null)
        surfaceProducer?.release()
        surfaceProducer = null

        pendingModelLoad = null
        pendingEnvironmentLoad = null
    }
}