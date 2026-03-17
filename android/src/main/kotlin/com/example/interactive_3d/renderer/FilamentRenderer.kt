package com.example.interactive_3d.renderer

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import com.google.android.filament.*
import com.google.android.filament.gltfio.*
import com.example.interactive_3d.Interactive3dCacheManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import java.nio.ByteBuffer

/**
 * Core Filament renderer for the interactive_3d plugin.
 *
 * Owns the Filament [Engine], [Renderer], [Scene], and [View], and
 * coordinates the sub-managers that handle camera, environment, model
 * loading, and entity selection. All Filament API calls happen on the
 * main thread; background work is limited to file I/O.
 *
 * Render loop uses [Choreographer] with adaptive frame pacing:
 * full 60 fps during interaction, 30 fps after a brief idle, and fully
 * paused after ~1.5 seconds of no input.
 */
class FilamentRenderer(
    private val context: Context,
    private var width: Int,
    private var height: Int
) {

    private companion object {
        const val TAG = "FilamentRenderer"
    }

    // Filament core objects
    private var engine: Engine? = null
    private var renderer: Renderer? = null
    private var scene: Scene? = null
    private var filamentView: View? = null
    private var camera: Camera? = null
    private var cameraEntity: Int = 0
    private var swapChain: SwapChain? = null

    // GLTF infrastructure
    private var materialProvider: MaterialProvider? = null
    private var assetLoader: AssetLoader? = null
    private var resourceLoader: ResourceLoader? = null

    // Sub-managers
    internal val cameraController = CameraController()
    internal val environment = EnvironmentLoader()
    internal val modelLoader = ModelLoader()
    internal val selection = SelectionManager()

    // Device-adaptive settings
    private val deviceTier: DeviceCapability.Tier
    private val quality: DeviceCapability.QualitySettings
    private val renderScale: Float

    // Render loop
    private val choreographer = Choreographer.getInstance()
    private var isRendering = false
    private val frameCallback = FrameCallback()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Background I/O (no Filament calls allowed on this scope)
    private val ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    init {
        deviceTier = DeviceCapability.detectTier(context)
        quality = DeviceCapability.settingsFor(deviceTier)
        renderScale = DeviceCapability.renderScaleFor(deviceTier)
        Log.d(TAG, "Device: $deviceTier, MSAA: ${quality.msaaSamples}x, scale: ${renderScale}x")

        initializeEngine()
    }

    // -------------------------------------------------------------------------
    // Engine Initialization
    // -------------------------------------------------------------------------

    private fun initializeEngine() {
        engine = Engine.create()
        val eng = engine ?: throw IllegalStateException("Failed to create Filament Engine")

        renderer = eng.createRenderer()
        scene = eng.createScene()
        filamentView = eng.createView().also { it.setScene(scene) }

        cameraEntity = EntityManager.get().create()
        camera = eng.createCamera(cameraEntity)
        filamentView?.camera = camera

        // Initial camera and exposure
        camera?.let { cam ->
            cameraController.applyProjection(cam, width, height)
            cameraController.applyToCamera(cam)
            cam.setExposure(16.0f, 1.0f / 125.0f, 50.0f)
        }

        environment.setupDefaultLighting(eng, scene!!)
        configureView()

        scene?.skybox = null

        // Post-processing disabled — color output goes straight to the surface.
        // MSAA still works at hardware level without the post-processing pipeline.
        filamentView?.isPostProcessingEnabled = true
        filamentView?.multiSampleAntiAliasingOptions = filamentView!!.multiSampleAntiAliasingOptions.apply {
            enabled = true
            sampleCount = 4
        }

        // Linear tone mapping avoids washed-out colors in the Texture API path
        filamentView?.colorGrading = ColorGrading.Builder()
            .toneMapper(ToneMapper.Linear())
            .build(eng)

        materialProvider = UbershaderProvider(eng)
        assetLoader = AssetLoader(eng, materialProvider!!, EntityManager.get())
        resourceLoader = ResourceLoader(eng, true)
    }

    /**
     * Configures Filament view options based on the detected device tier.
     *
     * Dynamic resolution is always disabled because certain Mali GPUs produce
     * blurred output when the internal resolution doesn't match the surface.
     */
    private fun configureView() {
        val v = filamentView ?: return

        v.antiAliasing = View.AntiAliasing.NONE

        // Dynamic resolution disabled to prevent GPU-driver blur on certain chipsets
        v.dynamicResolutionOptions = v.dynamicResolutionOptions.apply {
            enabled = false
            quality = View.QualityLevel.HIGH
        }

        v.multiSampleAntiAliasingOptions = v.multiSampleAntiAliasingOptions.apply {
            enabled = quality.msaaSamples > 0
            sampleCount = quality.msaaSamples
        }

        v.ambientOcclusionOptions = v.ambientOcclusionOptions.apply {
            enabled = false
            quality = if (deviceTier == DeviceCapability.Tier.HIGH_END)
                View.QualityLevel.HIGH else View.QualityLevel.LOW
        }

        v.bloomOptions = v.bloomOptions.apply {
            enabled = false
            quality = if (deviceTier == DeviceCapability.Tier.HIGH_END)
                View.QualityLevel.HIGH else View.QualityLevel.LOW
        }

        v.temporalAntiAliasingOptions = v.temporalAntiAliasingOptions.apply { enabled = false }
        v.dithering = View.Dithering.TEMPORAL
        v.blendMode = if (environment.useSolidBackground)
            View.BlendMode.OPAQUE else View.BlendMode.TRANSLUCENT

        v.renderQuality = v.renderQuality.apply {
            hdrColorBuffer = if (deviceTier == DeviceCapability.Tier.HIGH_END)
                View.QualityLevel.HIGH else View.QualityLevel.MEDIUM
        }

        renderer?.let { environment.applyClearColor(it) }
    }

    // -------------------------------------------------------------------------
    // SwapChain / Surface
    // -------------------------------------------------------------------------

    fun createSwapChain(surface: Surface) {
        val eng = engine ?: return
        destroySwapChain()

        // In createSwapChain, when solid background is used:
        swapChain = if (environment.useSolidBackground) {
            eng.createSwapChain(surface)  // No flags = opaque
        } else {
            eng.createSwapChain(surface, SwapChainFlags.CONFIG_TRANSPARENT)
        }
        filamentView?.viewport = Viewport(0, 0, width, height)
        camera?.let {
            cameraController.applyProjection(it, width, height)
            cameraController.applyToCamera(it)
        }
    }

    fun destroySwapChain() {
        swapChain?.let { engine?.destroySwapChain(it) }
        swapChain = null
    }

    fun updateViewport(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        this.width = width
        this.height = height

        filamentView?.viewport = Viewport(0, 0, width, height)
        camera?.let { cameraController.applyProjection(it, width, height) }
    }

    // -------------------------------------------------------------------------
    // Render Loop
    // -------------------------------------------------------------------------

    fun startRenderLoop() {
        if (isRendering) return
        isRendering = true
        choreographer.postFrameCallback(frameCallback)
    }

    fun stopRenderLoop() {
        isRendering = false
        choreographer.removeFrameCallback(frameCallback)
    }

    /**
     * Wakes the render loop from idle so that material/scene changes
     * are drawn to screen. Call after any programmatic visual change
     * (clear, refresh, visibility toggle, etc.).
     */
    private fun requestRender() {
        cameraController.markInteracting()
    }

    // -------------------------------------------------------------------------
    // Model Loading
    // -------------------------------------------------------------------------

    fun loadModel(
        buffer: ByteBuffer,
        fileName: String,
        resources: Map<String, ByteArray>,
        preselectedEntities: List<String>?,
        selectionColor: List<Double>?,
        patchColors: List<Map<String, Any>>?,
        enableCache: Boolean,
        cacheColor: List<Double>?,
        clearSelectionsOnHighlight: Boolean = false
    ) {
        val eng = engine ?: return
        val scn = scene ?: return
        val loader = assetLoader ?: return
        val resLoader = resourceLoader ?: return

        // Clean up previous model
        selection.reset(eng)
        selection.iblLoaded = environment.iblLoaded
        modelLoader.cleanupCurrentModel(scn, loader)

        // Configure selection
        selection.selectionColor = selectionColor.toFloatArrayOrDefault(floatArrayOf(0f, 1f, 0f, 1f))
        selection.patchColors = patchColors
        selection.enableCache = enableCache
        selection.clearSelectionsOnHighlight = clearSelectionsOnHighlight

        if (enableCache) {
            selection.cacheColor = cacheColor.toFloatArrayOrDefault(floatArrayOf(0.8f, 0.8f, 0.2f, 0.6f))
            selection.cacheManager = Interactive3dCacheManager(context, fileName, selection.cacheColor)
        }

        // Load
        val asset = modelLoader.loadModel(eng, scn, loader, resLoader, buffer, fileName, resources)
            ?: return

        // Fit camera to model
        modelLoader.getBoundingBox()?.let { (center, halfExtent) ->
            cameraController.fitToBoundingBox(center, halfExtent)
            camera?.let {
                cameraController.applyProjection(it, width, height)
                cameraController.applyToCamera(it)
            }
        }

        // Apply preselections and cache highlights
        selection.applyPreselections(preselectedEntities, asset, eng)
        if (enableCache) {
            selection.highlightCachedEntities(asset, eng)
            selection.notifyCacheChanged()
        }
    }

    // -------------------------------------------------------------------------
    // Environment
    // -------------------------------------------------------------------------

    fun loadEnvironment(iblBuffer: ByteBuffer, skyboxBuffer: ByteBuffer) {
        val eng = engine ?: return
        val scn = scene ?: return

        environment.loadEnvironment(eng, scn, iblBuffer, skyboxBuffer)

        // Enable AO/bloom now that IBL is loaded
        filamentView?.apply {
            ambientOcclusionOptions = ambientOcclusionOptions.apply { enabled = this@FilamentRenderer.quality.enableAO }
            bloomOptions = bloomOptions.apply { enabled = this@FilamentRenderer.quality.enableBloom }
        }

        // Remove default emissive now that IBL provides ambient light
        modelLoader.restoreEmissiveAfterIBL(eng)

        // Selection manager needs to know IBL state for correct reset behavior
        selection.iblLoaded = true
    }

    fun setBackgroundColor(color: List<Double>) {
        val rend = renderer ?: return
        val scn = scene ?: return
        environment.setBackgroundColor(color, rend, scn)
    }

    // -------------------------------------------------------------------------
    // Gestures
    // -------------------------------------------------------------------------

    fun onTap(x: Int, y: Int) {
        cameraController.markInteracting()
        val v = filamentView ?: return
        val flippedY = height - y

        v.pick(x, flippedY, mainHandler) { result ->
            val entity = result.renderable
            if (entity == 0) return@pick

            val asset = modelLoader.currentAsset ?: return@pick
            val isModelEntity = asset.entities?.contains(entity) ?: false
            if (!isModelEntity) return@pick

            val eng = engine ?: return@pick
            selection.handleTap(entity, asset, eng)
        }
    }

    fun onPan(deltaX: Float, deltaY: Float) {
        if (cameraController.onPan(deltaX, deltaY)) {
            camera?.let { cameraController.applyToCamera(it) }
        }
    }

    fun onScale(scale: Float) {
        if (cameraController.onScale(scale)) {
            // Re-lock render quality during zoom to prevent driver-side blur
            filamentView?.let { v ->
                v.dynamicResolutionOptions = v.dynamicResolutionOptions.apply {
                    enabled = false
                    quality = View.QualityLevel.HIGH
                }
                v.renderQuality = v.renderQuality.apply {
                    hdrColorBuffer = View.QualityLevel.HIGH
                }
            }
            camera?.let {
                cameraController.applyProjection(it, width, height)
                cameraController.applyToCamera(it)
            }
        }
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    fun setCameraZoomLevel(zoom: Float) {
        cameraController.setZoom(zoom)
        camera?.let {
            cameraController.applyProjection(it, width, height)
            cameraController.applyToCamera(it)
        }
    }

    fun setPartGroupVisibility(group: Map<String, Any>, isVisible: Boolean) {
        val asset = modelLoader.currentAsset ?: return
        val scn = scene ?: return
        @Suppress("UNCHECKED_CAST")
        val names = (group["names"] as? List<*>)?.filterIsInstance<String>() ?: return

        asset.entities?.forEach { entity ->
            val name = asset.getName(entity)
            if (name != null && names.contains(name)) {
                if (isVisible) scn.addEntity(entity) else scn.removeEntity(entity)
                selection.entityVisibilities[entity] = isVisible
            }
        }

        // Force a render frame so the visibility change is visible immediately
        cameraController.markInteracting()

        if (!isVisible) {
            val eng = engine ?: return
            names.forEach { name ->
                asset.entities?.find { asset.getName(it) == name }?.let { entity ->
                    if (selection.selectedEntities.contains(entity)) {
                        selection.resetColor(entity, eng)
                        selection.selectedEntities.remove(entity)
                    }
                }
            }
            selection.onSelectionChanged?.invoke(
                selection.selectedEntities.mapNotNull { e ->
                    val n = asset.getName(e)
                    if (n != null && n != "Unnamed Entity") mapOf("id" to e.toLong(), "name" to n) else null
                }
            )
        }
    }

    fun unselectEntities(entityIds: List<Long>?) {
        val eng = engine ?: return
        selection.unselectEntities(entityIds, eng, modelLoader.currentAsset)
        requestRender()
    }

    fun clearCacheAndRestoreSelections() {
        val eng = engine ?: return
        val asset = modelLoader.currentAsset ?: return
        selection.clearCacheAndRestore(asset, eng)
        requestRender()
    }

    fun refreshCacheHighlights() {
        val eng = engine ?: return
        val asset = modelLoader.currentAsset ?: return
        selection.refreshAllHighlights(asset, eng, selection.clearSelectionsOnHighlight)
        selection.notifySelectionChanged(asset)
        selection.notifyCacheChanged()
        requestRender()
    }

    fun removeFromCache(names: List<String>) {
        val eng = engine ?: return
        val asset = modelLoader.currentAsset ?: return
        names.forEach { name ->
            selection.cacheManager?.removeFromCache(name)
            asset.entities?.find { asset.getName(it) == name }?.let { entity ->
                selection.resetColor(entity, eng)
                selection.selectedEntities.remove(entity)
            }
        }
        selection.onSelectionChanged?.invoke(
            selection.selectedEntities.mapNotNull { e ->
                val n = asset.getName(e)
                if (n != null) mapOf("id" to e.toLong(), "name" to n) else null
            }
        )
        selection.notifyCacheChanged()
        requestRender()
    }

    fun setSelectionListener(listener: (List<Map<String, Any>>) -> Unit) {
        selection.onSelectionChanged = listener
    }

    fun setCacheSelectionListener(listener: (List<Map<String, Any>>) -> Unit) {
        selection.onCacheSelectionChanged = listener
    }

    // -------------------------------------------------------------------------
    // Cleanup
    // -------------------------------------------------------------------------

    fun cleanup() {
        stopRenderLoop()

        val eng = engine ?: return

        selection.cleanup(eng)
        cameraController.cancelCallbacks()
        ioScope.cancel()

        modelLoader.cleanupCurrentModel(scene!!, assetLoader!!)
        environment.cleanup(eng, scene!!)

        resourceLoader?.destroy()
        assetLoader?.destroy()
        materialProvider?.destroyMaterials()
        materialProvider?.destroy()

        destroySwapChain()

        filamentView?.let { eng.destroyView(it) }
        scene?.let { eng.destroyScene(it) }
        renderer?.let { eng.destroyRenderer(it) }

        if (cameraEntity != 0) {
            eng.destroyCameraComponent(cameraEntity)
            EntityManager.get().destroy(cameraEntity)
        }

        eng.destroy()

        engine = null
        renderer = null
        scene = null
        filamentView = null
        camera = null
        materialProvider = null
        assetLoader = null
        resourceLoader = null
        cameraEntity = 0
    }

    // -------------------------------------------------------------------------
    // Frame Callback
    // -------------------------------------------------------------------------

    private inner class FrameCallback : Choreographer.FrameCallback {
        private val startTime = System.nanoTime()
        private var frameCount = 0

        override fun doFrame(frameTimeNanos: Long) {
            if (!isRendering) return
            choreographer.postFrameCallback(this)

            // Adaptive frame pacing based on user interaction
            if (!cameraController.isInteracting) {
                cameraController.idleFrameCount++
                if (cameraController.idleFrameCount > 90) return       // Fully idle — save battery
                if (cameraController.idleFrameCount > 30 && frameCount % 2 != 0) return // 30 fps
            }

            val rend = renderer ?: return
            val sc = swapChain ?: return
            val v = filamentView ?: return

            // Animate if the model has animations
            modelLoader.currentAsset?.instance?.animator?.apply {
                if (animationCount > 0) {
                    val elapsed = (frameTimeNanos - startTime) / 1_000_000_000.0
                    applyAnimation(0, elapsed.toFloat())
                    updateBoneMatrices()
                }
            }

            try {
                if (rend.beginFrame(sc, frameTimeNanos)) {
                    rend.render(v)
                    rend.endFrame()
                    frameCount++
                }
            } catch (e: Exception) {
                Log.e(TAG, "Render error: ${e.message}")
            }
        }
    }
}

// -------------------------------------------------------------------------
// Extension
// -------------------------------------------------------------------------

/**
 * Converts a nullable List<Double> to a FloatArray, or returns [default].
 */
private fun List<Double>?.toFloatArrayOrDefault(default: FloatArray): FloatArray {
    if (this == null || size != 4) return default
    return floatArrayOf(get(0).toFloat(), get(1).toFloat(), get(2).toFloat(), get(3).toFloat())
}