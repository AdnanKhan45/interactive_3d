package com.example.interactive_3d

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer

/**
 * Interactive3dTextureEntry manages the lifecycle of a Flutter SurfaceProducer
 * and connects it to the Filament renderer.
 *
 * Key responsibilities:
 * - Create and manage SurfaceProducer from Flutter's TextureRegistry
 * - Handle surface lifecycle events (onSurfaceAvailable, onSurfaceCleanup)
 * - Delegate rendering to FilamentTextureRenderer
 * - Route method calls and events between Flutter and the renderer
 */
class Interactive3dTextureEntry(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val messenger: BinaryMessenger,
    private val width: Int,
    private val height: Int
) : TextureRegistry.SurfaceProducer.Callback {

    companion object {
        private const val TAG = "Interactive3dTexture"
    }

    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
    private var filamentRenderer: FilamentTextureRenderer? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    // Pending operations to execute once surface is available
    private var pendingModelLoad: (() -> Unit)? = null
    private var pendingEnvironmentLoad: (() -> Unit)? = null

    // Store configuration for recreation after surface lifecycle
    private var currentWidth: Int = width
    private var currentHeight: Int = height

    /**
     * Initializes the SurfaceProducer and returns the texture ID.
     * Returns -1 if initialization fails.
     */
    fun initialize(): Long {
        try {
            // Create SurfaceProducer using the modern API
            surfaceProducer = textureRegistry.createSurfaceProducer()

            val producer = surfaceProducer ?: run {
                Log.e(TAG, "Failed to create SurfaceProducer")
                return -1L
            }

            // Set the size before setting callback
            producer.setSize(width, height)

            // Set callback for surface lifecycle events
            // IMPORTANT: The renderer will be initialized in onSurfaceAvailable callback
            producer.setCallback(this)

            val textureId = producer.id()

            // Setup event channel for this texture
            eventChannel = EventChannel(messenger, "interactive_3d_events_$textureId")
            eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

            Log.d(TAG, "Initialized SurfaceProducer with ID: $textureId")

            // Try to initialize if surface is already available
            // But this might not work - we rely on onSurfaceAvailable callback
            mainHandler.post {
                initializeRendererIfSurfaceAvailable()
            }

            return textureId

        } catch (e: Exception) {
            Log.e(TAG, "Error initializing texture entry: ${e.message}", e)
            return -1L
        }
    }

    /**
     * Called by Flutter when surface becomes available (app resumed, etc.)
     */
    override fun onSurfaceAvailable() {
        Log.d(TAG, ">>> onSurfaceAvailable called <<<")
        mainHandler.post {
            Log.d(TAG, "onSurfaceAvailable - initializing renderer on main thread")
            initializeRendererIfSurfaceAvailable()

            // Execute any pending operations
            pendingModelLoad?.invoke()
            pendingModelLoad = null

            pendingEnvironmentLoad?.invoke()
            pendingEnvironmentLoad = null
        }
    }

    /**
     * Called by Flutter when surface is about to be destroyed (app backgrounded, low memory)
     */
    override fun onSurfaceCleanup() {
        Log.d(TAG, "onSurfaceCleanup called")
        mainHandler.post {
            // Stop rendering but don't destroy the renderer fully
            // We'll recreate the SwapChain when surface becomes available again
            filamentRenderer?.destroySwapChain()
        }
    }

    /**
     * Initialize the Filament renderer if surface is available
     */
    private fun initializeRendererIfSurfaceAvailable() {
        val producer = surfaceProducer ?: return

        // Always get a fresh surface
        val surface = producer.getSurface()

        Log.d(TAG, "Checking surface - isValid: ${surface.isValid}")

        if (!surface.isValid) {
            Log.w(TAG, "Surface not yet valid, waiting for onSurfaceAvailable")
            return
        }

        if (filamentRenderer == null) {
            // First time initialization
            Log.d(TAG, "Creating new FilamentTextureRenderer")
            filamentRenderer = FilamentTextureRenderer(
                context = context,
                width = currentWidth,
                height = currentHeight
            )
            filamentRenderer?.setSelectionListener { entities ->
                sendSelectionEvent(entities)
            }
            filamentRenderer?.setCacheSelectionListener { entities ->
                sendCacheSelectionEvent(entities)
            }
        }

        // Get fresh surface again for SwapChain (important!)
        val freshSurface = producer.getSurface()
        Log.d(TAG, "Creating SwapChain with fresh surface - isValid: ${freshSurface.isValid}")

        // Create or recreate the SwapChain with the current surface
        filamentRenderer?.createSwapChain(freshSurface)
        filamentRenderer?.startRenderLoop()

        Log.d(TAG, "Renderer initialized with surface")
    }

    /**
     * Updates the texture size. Call this when the widget size changes.
     */
    fun updateSize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return

        currentWidth = width
        currentHeight = height

        surfaceProducer?.setSize(width, height)
        filamentRenderer?.updateViewport(width, height)
    }

    /**
     * Loads a 3D model.
     */
    fun loadModel(
        buffer: ByteBuffer,
        fileName: String,
        resources: Map<String, ByteArray>,
        preselectedEntities: List<String>?,
        selectionColor: List<Double>?,
        patchColors: List<Map<String, Any>>?,
        enableCache: Boolean,
        cacheColor: List<Double>?
    ) {
        val loadOperation = {
            filamentRenderer?.loadModel(
                buffer = buffer,
                fileName = fileName,
                resources = resources,
                preselectedEntities = preselectedEntities,
                selectionColor = selectionColor,
                patchColors = patchColors,
                enableCache = enableCache,
                cacheColor = cacheColor
            )
        }

        if (filamentRenderer != null && surfaceProducer?.getSurface()?.isValid == true) {
            mainHandler.post { loadOperation() }
        } else {
            // Store for later execution when surface is available
            pendingModelLoad = { loadOperation(); Unit }
        }
    }

    /**
     * Loads environment lighting.
     */
    fun loadEnvironment(iblBuffer: ByteBuffer, skyboxBuffer: ByteBuffer) {
        val loadOperation = {
            filamentRenderer?.loadEnvironment(iblBuffer, skyboxBuffer)
        }

        if (filamentRenderer != null && surfaceProducer?.getSurface()?.isValid == true) {
            mainHandler.post { loadOperation() }
        } else {
            pendingEnvironmentLoad = { loadOperation(); Unit }
        }
    }

    /**
     * Sets camera zoom level.
     */
    fun setCameraZoomLevel(zoom: Float) {
        mainHandler.post {
            filamentRenderer?.setCameraZoomLevel(zoom)
        }
    }

    /**
     * Sets visibility for a model part group.
     */
    fun setPartGroupVisibility(group: Map<String, Any>, isVisible: Boolean) {
        mainHandler.post {
            filamentRenderer?.setPartGroupVisibility(group, isVisible)
        }
    }

    /**
     * Unselects entities.
     */
    fun unselectEntities(entityIds: List<Long>?) {
        mainHandler.post {
            filamentRenderer?.unselectEntities(entityIds)
        }
    }

    /**
     * Clears selection cache.
     */
    fun clearCache() {
        mainHandler.post {
            filamentRenderer?.clearCacheAndRestoreSelections()
        }
    }

    /**
     * Handles tap at the given coordinates.
     */
    fun onTap(x: Float, y: Float) {
        mainHandler.post {
            filamentRenderer?.onTap(x.toInt(), y.toInt())
        }
    }

    /**
     * Handles pan gesture.
     */
    fun onPan(deltaX: Float, deltaY: Float) {
        mainHandler.post {
            filamentRenderer?.onPan(deltaX, deltaY)
        }
    }

    /**
     * Handles scale (pinch) gesture.
     */
    fun onScale(scale: Float) {
        mainHandler.post {
            filamentRenderer?.onScale(scale)
        }
    }

    fun setBackgroundColor(color: List<Double>) {
        filamentRenderer?.setBackgroundColor(color)
    }

    /**
     * Sends selection changed event to Flutter.
     */
    private fun sendSelectionEvent(entities: List<Map<String, Any>>) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "event" to "selectionChanged",
                    "selectedEntities" to entities
                )
            )
        }
    }

    /**
     * Sends cache selection changed event to Flutter.
     */
    private fun sendCacheSelectionEvent(entities: List<Map<String, Any>>) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "event" to "cacheSelectionChanged",
                    "cachedEntities" to entities
                )
            )
        }
    }

    /**
     * Disposes all resources.
     */
    fun dispose() {
        Log.d(TAG, "Disposing Interactive3dTextureEntry")

        // Clear event handling
        eventSink = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null

        // Remove handler callbacks
        mainHandler.removeCallbacksAndMessages(null)

        // Cleanup Filament renderer
        filamentRenderer?.cleanup()
        filamentRenderer = null

        // Release the SurfaceProducer
        surfaceProducer?.setCallback(null)
        surfaceProducer?.release()
        surfaceProducer = null

        // Clear pending operations
        pendingModelLoad = null
        pendingEnvironmentLoad = null

        Log.d(TAG, "Interactive3dTextureEntry disposed")
    }
}