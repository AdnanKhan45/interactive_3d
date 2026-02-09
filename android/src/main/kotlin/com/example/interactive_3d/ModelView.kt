package com.example.interactive_3d

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.util.Log
import android.view.Choreographer
import android.view.GestureDetector
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.TextureView
import android.widget.LinearLayout
import com.google.android.filament.Fence
import com.google.android.filament.View
import com.google.android.filament.utils.AutomationEngine
import com.google.android.filament.utils.KTX1Loader
import com.google.android.filament.utils.ModelViewer
import com.google.android.filament.Camera
import java.nio.ByteBuffer
import java.util.concurrent.Executor

/**
 * A custom view for rendering and interacting with 3D models using Filament.
 */
class ModelView : LinearLayout {

    private val TAG = "ModelView"

    // UI components
    private lateinit var textureView: TextureView
    private lateinit var choreographer: Choreographer
    private val frameScheduler = FrameCallback()
    private lateinit var modelViewer: ModelViewer
    private val automation = AutomationEngine()

    // State variables
    private var loadStartTime = 0L
    private var loadStartFence: Fence? = null
    private val viewerContent = AutomationEngine.ViewerContent()
    private lateinit var singleTapDetector: GestureDetector
    private val singleTapListener = SingleTapListener()
    private val selectedEntities = mutableSetOf<Int>()
    private val resourceMap = mutableMapOf<String, ByteBuffer>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { command -> mainHandler.post(command) }
    private var activityLifecycleCallbacks: Application.ActivityLifecycleCallbacks? = null
    private var pendingPreselectedEntities: List<String>? = null
    private var modelLoaded = false
    private var selectionColor: FloatArray? = null // Store RGBA as [r, g, b, a]
    private var patchColors: List<Map<String, Any>>? = null // Store entity-specific colors
    private val entityVisibilities = mutableMapOf<Int, Boolean>() // Track entity visibility

    // Caching
    var enableCache: Boolean = false
    var cacheManager: Interactive3dCacheManager? = null
    private var cacheColor: FloatArray = floatArrayOf(0.8f, 0.8f, 0.2f, 0.6f)
    private var modelCacheKey: String = ""

    /**
     * Listener interface for selection changes in the 3D model.
     */
    interface SelectionListener {
        fun onSelectionChanged(selectedEntities: List<Map<String, Any>>)
    }

    private var selectionListener: SelectionListener? = null

    /**
     * Sets the selection listener for the view.
     * @param listener The listener to be notified of selection changes.
     */
    fun setSelectionListener(listener: SelectionListener) {
        selectionListener = listener
    }

    interface CacheSelectionListener {
        fun onCacheSelectionChanged(cachedEntities: List<Map<String, Any>>)
    }

    interface LoadingStateListener {
        fun onLoadingStateChanged(isLoading: Boolean)
    }

    private var cacheSelectionListener: CacheSelectionListener? = null
    private var loadingStateListener: LoadingStateListener? = null

    fun setCacheSelectionListener(listener: CacheSelectionListener) {
        cacheSelectionListener = listener
    }

    fun setLoadingStateListener(listener: LoadingStateListener) {
        loadingStateListener = listener
    }


    // Constructors
    constructor(context: Context?) : super(context) { init(context) }
    constructor(context: Context?, attrs: AttributeSet?) : super(context, attrs) { init(context) }
    constructor(context: Context?, attrs: AttributeSet?, defStyleAttr: Int) : super(context, attrs, defStyleAttr) { init(context) }
    constructor(context: Context?, attrs: AttributeSet?, defStyleAttr: Int, defStyleRes: Int) : super(context, attrs, defStyleAttr, defStyleRes) { init(context) }

    /**
     * Initializes the view and its components.
     * @param context The context in which the view is running.
     */
    @SuppressLint("ClickableViewAccessibility")
    private fun init(context: Context?) {
        val inflated = LayoutInflater.from(context).inflate(R.layout.custom_view, this, true)
        textureView = inflated.findViewById(R.id.main_sv)

        singleTapDetector = GestureDetector(context, singleTapListener)

        choreographer = Choreographer.getInstance()

        // Create ModelViewer with default engine (one per view)
        // NOTE: Engine singleton approach doesn't work due to ModelViewer internals
        // The REAL performance gain comes from model caching, not engine reuse
        modelViewer = ModelViewer(textureView)
        Log.d(TAG, "ModelView created with new engine (model caching provides speed)")

        viewerContent.view = modelViewer.view
        viewerContent.sunlight = modelViewer.light
        viewerContent.lightManager = modelViewer.engine.lightManager
        viewerContent.scene = modelViewer.scene
        viewerContent.renderer = modelViewer.renderer

        textureView.setOnTouchListener { _, event ->
            modelViewer.onTouchEvent(event)
            singleTapDetector.onTouchEvent(event)
            true
        }

        choreographer.postFrameCallback(frameScheduler)

        // Store lifecycle callbacks reference so we can unregister later
        activityLifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: android.os.Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityResumed(activity: Activity) {
                choreographer.postFrameCallback(frameScheduler)
            }
            override fun onActivityPaused(activity: Activity) {
                choreographer.removeFrameCallback(frameScheduler)
            }
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: android.os.Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {
                choreographer.removeFrameCallback(frameScheduler)
                cleanup()
            }
        }

        // Register the callbacks only if we successfully created them
        activityLifecycleCallbacks?.let { callbacks ->
            (context as? Activity)?.registerActivityLifecycleCallbacks(callbacks)
        }
    }


    /**
     * Sets the visibility of a group of model parts.
     * @param group A map containing 'title' (String) and 'names' (List<String>) of entities.
     * @param isVisible Whether the group’s parts should be visible (true) or invisible (false).
     */
    fun setPartGroupVisibility(group: Map<String, Any>, isVisible: Boolean) {
        val title = group["title"] as? String ?: run {
            Log.e(TAG, "Invalid group data: missing title")
            return
        }
        val names = group["names"] as? List<String> ?: run {
            Log.e(TAG, "Invalid group data: missing names for title $title")
            return
        }

        Log.d(TAG, "Setting visibility for group '$title' to ${if (isVisible) "visible" else "invisible"}")

        var updatedEntities = 0
        modelViewer.asset?.getEntities()?.forEach { entity ->
            val entityName = modelViewer.asset?.getName(entity)
            if (entityName != null && names.contains(entityName)) {
                val rcm = modelViewer.engine.renderableManager
                if (rcm.hasComponent(entity)) {
                    if (isVisible) {
                        modelViewer.scene.addEntity(entity)
                    } else {
                        modelViewer.scene.removeEntity(entity)
                    }
                    entityVisibilities[entity] = isVisible
                    updatedEntities++
                    Log.d(TAG, "Set visibility to $isVisible for entity: $entityName")
                } else {
                    Log.w(TAG, "Entity $entityName has no renderable component")
                }
            }
        }

        if (updatedEntities == 0) {
            Log.w(TAG, "No entities updated for group '$title'. Expected names: ${names.joinToString(", ")}")
        } else {
            Log.d(TAG, "Updated $updatedEntities entities for group '$title'")
        }

        // Ensure selections respect visibility
        if (!isVisible) {
            unselectEntities(names.mapNotNull { name ->
                modelViewer.asset?.getEntities()?.find { modelViewer.asset?.getName(it) == name }?.toLong()
            })
        }
    }


    /**
     * Sets the zoom level for the camera.
     * @param zoom The zoom level to set.
     */
    fun setCameraZoomLevel(zoom: Float) {
        val width = textureView.width.takeIf { it != 0 } ?: return
        val height = textureView.height.takeIf { it != 0 } ?: return

        val camera = modelViewer.camera
        val aspect = width.toDouble() / height.toDouble()
        val near = 0.1
        val far = 100.0

        val defaultFov = 50.0
        val newFov = defaultFov / zoom

        camera.setProjection(
            newFov,
            aspect,
            near,
            far,
            Camera.Fov.VERTICAL
        )

        Log.d(TAG, "Camera zoom set: zoom = $zoom, newFov = $newFov")
    }


    /**
     * Cleans up the previous model's resources before loading a new one.
     * This prevents memory accumulation across multiple model loads.
     */
    private fun cleanupPreviousModel() {
        Log.d(TAG, "Cleaning up previous model resources")

        // 1. Clear selections - important to release entity references
        selectedEntities.clear()

        // 2. Clear resource map - THIS IS KEY FIX FOR MEMORY LEAK
        // The resourceMap was accumulating ByteBuffers indefinitely
        val previousResourceCount = resourceMap.size
        resourceMap.clear()
        Log.d(TAG, "Cleared $previousResourceCount resources from resource map")

        // 3. Clear entity visibilities tracking
        entityVisibilities.clear()

        // 4. Destroy the previous model to free GPU resources
        try {
            if (modelLoaded) {
                modelViewer.destroyModel()
                Log.d(TAG, "Destroyed previous model")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error destroying previous model: ${e.message}")
        }

        // 5. Clear pending preselected entities
        pendingPreselectedEntities = null

        // 6. Reset model loaded flag
        modelLoaded = false

        Log.d(TAG, "Previous model cleanup completed")
    }

    /**
     * Loads a 3D model (GLB or GLTF) with optional preselected entities, selection color, and patch colors.
     */
    fun setModel(
        buffer: ByteBuffer,
        fileName: String,
        resources: Map<String, ByteArray>,
        preselectedEntities: List<String>?,
        selectionColor: List<Double>?,
        patchColors: List<Map<String, Any>>?,
        enableCache: Boolean,
        cacheColor: List<Double>?
    ) {
        // Notify loading started
        loadingStateListener?.onLoadingStateChanged(true)

        // OPTIMIZATION: Start with fast rendering mode for instant display
        setViewOptions(fastMode = true)

        // CRITICAL: Clean up previous model resources before loading new one
        cleanupPreviousModel()

        // Send updates after cleanup
        sendSelectedEntitiesToFlutter()
        sendCacheSelectionUpdate()

        this.pendingPreselectedEntities = preselectedEntities
        this.selectionColor = if (selectionColor?.size == 4) {
            floatArrayOf(
                selectionColor[0].toFloat(),
                selectionColor[1].toFloat(),
                selectionColor[2].toFloat(),
                selectionColor[3].toFloat()
            )
        } else {
            floatArrayOf(0.0f, 1.0f, 0.0f, 1.0f) // Default green
        }
        this.patchColors = patchColors

        this.enableCache = enableCache
        if (enableCache) {
            val color = if (cacheColor != null && cacheColor.size == 4) {
                floatArrayOf(
                    cacheColor[0].toFloat(),
                    cacheColor[1].toFloat(),
                    cacheColor[2].toFloat(),
                    cacheColor[3].toFloat()
                )
            } else {
                floatArrayOf(0.8f, 0.8f, 0.2f, 0.6f) // Default cache color
            }
            cacheManager = Interactive3dCacheManager(context, fileName, color)
            sendCacheSelectionUpdate()
        } else {
            cacheManager = null
        }

        setModel(buffer, fileName, resources)
    }


    /**
     * Loads a 3D model (GLB or GLTF) with caching and performance optimizations.
     */
    private fun setModel(buffer: ByteBuffer, fileName: String, resources: Map<String, ByteArray>) {
        val startTime = System.nanoTime()

        val cached = ModelCacheManager.get(fileName)
        if (cached != null) {
            cached.buffer.rewind()
            if (fileName.endsWith(".gltf", ignoreCase = true)) {
                modelViewer.loadModelGltfAsync(cached.buffer) { resourcePath ->
                    resourceMap[resourcePath] ?: ByteBuffer.allocate(0)
                }
            } else if (fileName.endsWith(".glb", ignoreCase = true)) {
                modelViewer.loadModelGlb(cached.buffer)
            }
            modelLoaded = true

            // ✅ CRITICAL: Release resources AFTER model is loaded to GPU
            mainHandler.postDelayed({
                resourceMap.clear()
                Log.d(TAG, "Released resource buffers after GPU upload")
            }, 500)  // Small delay to ensure GPU upload completes

        } else {
            modelLoaded = false

            // Temporarily store resources for loading
            resources.forEach { (key, value) ->
                resourceMap[key] = ByteBuffer.wrap(value)
            }

            if (fileName.endsWith(".gltf", ignoreCase = true)) {
                modelViewer.loadModelGltfAsync(buffer) { resourcePath ->
                    resourceMap[resourcePath] ?: run {
                        Log.e(TAG, "Missing resource: $resourcePath")
                        ByteBuffer.allocate(0)
                    }
                }
            } else if (fileName.endsWith(".glb", ignoreCase = true)) {
                modelViewer.loadModelGlb(buffer)
            }

            modelViewer.asset?.let { asset ->
                buffer.rewind()
                ModelCacheManager.put(fileName, asset, buffer)
            }

            modelLoaded = true

            // ✅ CRITICAL: Release resources after model is on GPU
            mainHandler.postDelayed({
                resourceMap.clear()
                Log.d(TAG, "Released ${resourceMap.size} resource buffers")
            }, 500)
        }

        if (automation.viewerOptions.autoScaleEnabled) {
            modelViewer.transformToUnitCube()
        } else {
            modelViewer.clearRootTransform()
        }

        loadStartTime = System.nanoTime()
        loadStartFence = modelViewer.engine.createFence()
    }

    /**
     * Sets the lighting for the 3D scene.
     * @param skyBox The skybox data.
     * @param indirectLight The indirect light data.
     */
    fun setLights(skyBox: ByteBuffer, indirectLight: ByteBuffer) {
        val engine = modelViewer.engine
        val scene = modelViewer.scene
        scene.indirectLight = KTX1Loader.createIndirectLight(engine, indirectLight)
        scene.indirectLight?.intensity = 30_000.0f
        viewerContent.indirectLight = scene.indirectLight
        scene.skybox = KTX1Loader.createSkybox(engine, skyBox)
        Log.d(TAG, "Environment set: skybox and indirect light loaded")
    }

    /**
     * Configures the view options for rendering.
     * OPTIMIZATION: Added fast loading mode to reduce initial render time.
     */
    fun setViewOptions(fastMode: Boolean = false) {
        val view = modelViewer.view

        if (fastMode) {
            // FAST LOADING MODE: Minimal quality for instant display
            Log.d(TAG, "Setting view options in FAST mode (lower quality for speed)")

            view.renderQuality = view.renderQuality.apply {
                hdrColorBuffer = View.QualityLevel.LOW
            }
            view.dynamicResolutionOptions = view.dynamicResolutionOptions.apply {
                enabled = false  // Disable for speed
            }
            view.multiSampleAntiAliasingOptions = view.multiSampleAntiAliasingOptions.apply {
                enabled = false  // Disable for speed
            }
            view.antiAliasing = View.AntiAliasing.NONE  // Fastest
            view.ambientOcclusionOptions = view.ambientOcclusionOptions.apply {
                enabled = false  // EXPENSIVE! Disable during loading
            }
            view.bloomOptions = view.bloomOptions.apply {
                enabled = false  // EXPENSIVE! Disable during loading
            }
        } else {
            // FULL QUALITY MODE: Beautiful rendering
            Log.d(TAG, "Setting view options in FULL QUALITY mode")

            view.renderQuality = view.renderQuality.apply {
                hdrColorBuffer = View.QualityLevel.MEDIUM
            }
            view.dynamicResolutionOptions = view.dynamicResolutionOptions.apply {
                enabled = true
                quality = View.QualityLevel.MEDIUM
            }
            view.multiSampleAntiAliasingOptions = view.multiSampleAntiAliasingOptions.apply {
                enabled = true
            }
            view.antiAliasing = View.AntiAliasing.FXAA
            view.ambientOcclusionOptions = view.ambientOcclusionOptions.apply {
                enabled = true
            }
            view.bloomOptions = view.bloomOptions.apply {
                enabled = true
            }
        }

        Log.d(TAG, "View options set (fastMode: $fastMode)")
    }

    /**
     * Comprehensive cleanup of all resources to prevent memory leaks.
     * Called when the view is being disposed or destroyed.
     */
    fun cleanup() {
        Log.d(TAG, "Starting comprehensive ModelView cleanup")

        choreographer.removeFrameCallback(frameScheduler)
        Log.d(TAG, "Removed choreographer callback")

        activityLifecycleCallbacks?.let { callbacks ->
            (context as? Activity)?.unregisterActivityLifecycleCallbacks(callbacks)
            activityLifecycleCallbacks = null
            Log.d(TAG, "Unregistered activity lifecycle callbacks")
        }

        selectedEntities.clear()
        resourceMap.clear()  // ✅ Release resource buffers
        entityVisibilities.clear()
        cacheManager = null

        try {
            automation.stopRunning()
            Log.d(TAG, "Stopped automation engine")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping automation: ${e.message}")
        }

        try {
            if (modelLoaded && modelViewer.asset != null) {
                modelViewer.destroyModel()
                Log.d(TAG, "Destroyed model safely")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error destroying model: ${e.message}")
        }

        // ✅ CRITICAL: Destroy the engine and renderer to free GPU resources
        try {
            modelViewer.renderer?.let { renderer ->
                // Clear render target
                modelViewer.view.renderTarget = null
            }

            // Destroy engine (this releases ALL GPU resources)
            modelViewer.engine?.destroy()
            Log.d(TAG, "Destroyed Filament engine and freed GPU memory")
        } catch (e: Exception) {
            Log.e(TAG, "Error destroying engine: ${e.message}")
        }

        selectionListener = null
        cacheSelectionListener = null
        loadingStateListener = null

        modelLoaded = false
        pendingPreselectedEntities = null

        Log.d(TAG, "ModelView cleanup completed successfully")
    }

    /**
     * Legacy destroy method - now calls cleanup for compatibility
     * @deprecated Use cleanup() instead
     */
    @Deprecated("Use cleanup() instead", ReplaceWith("cleanup()"))
    fun destroy() {
        cleanup()
    }

    private fun getEntityColor(entityName: String?): FloatArray {
        if (entityName == null) return selectionColor ?: floatArrayOf(0.0f, 1.0f, 0.0f, 1.0f)

        patchColors?.forEach { patch ->
            if (patch["name"] == entityName) {
                val color = patch["color"] as? List<Double>
                if (color?.size == 4) {
                    return floatArrayOf(
                        color[0].toFloat(),
                        color[1].toFloat(),
                        color[2].toFloat(),
                        color[3].toFloat()
                    )
                }
            }
        }
        return selectionColor ?: floatArrayOf(0.0f, 1.0f, 0.0f, 1.0f) // Fallback to global color
    }

    private fun applyPreselectedEntities() {
        if (pendingPreselectedEntities == null || !modelLoaded) return

        pendingPreselectedEntities?.forEach { name ->
            modelViewer.asset?.getEntities()?.forEach { entity ->
                val entityName = modelViewer.asset?.getName(entity)
                if (name == entityName && entity !in selectedEntities) {
                    val color = getEntityColor(entityName)
                    setRenderableColor(entity, color[0], color[1], color[2], color[3])
                    selectedEntities.add(entity)
                }
            }
        }

        sendSelectedEntitiesToFlutter()
        pendingPreselectedEntities = null
    }

    private fun sendSelectedEntitiesToFlutter() {
        val asset = modelViewer.asset ?: return
        val items = mutableListOf<Map<String, Any>>()
        for (entity in selectedEntities) {
            val name = asset.getName(entity)
            if (name != null && name != "Unnamed Entity") {
                items.add(mapOf("id" to entity.toLong(), "name" to name))
            }
        }
        selectionListener?.onSelectionChanged(items)
    }


    fun sendCacheSelectionUpdate() {
        val cached = cacheManager?.cachedEntities?.map { mapOf("name" to it) } ?: emptyList()
        cacheSelectionListener?.onCacheSelectionChanged(cached)
    }

    /**
     * Unselects the specified entities or all entities if none are provided.
     * @param entities List of entity IDs to unselect, or null to unselect all.
     */
    fun unselectEntities(entities: List<Long>? = null) {
        if (entities == null) {
            // Clear all selections
            selectedEntities.forEach { entity ->
                resetRenderableColor(entity)
            }
            selectedEntities.clear()
        } else {
            // Unselect specific entities
            entities.forEach { entityId ->
                val entity = entityId.toInt()
                if (selectedEntities.contains(entity)) {
                    resetRenderableColor(entity)
                    selectedEntities.remove(entity)
                }
            }
        }
        sendSelectedEntitiesToFlutter()
    }

    private fun setRenderableColor(entity: Int, r: Float, g: Float, b: Float, a: Float) {
        val rcm = modelViewer.engine.renderableManager
        if (!rcm.hasComponent(entity)) return
        val ri = rcm.getInstance(entity)
        val count = rcm.getPrimitiveCount(ri)
        for (i in 0 until count) {
            val materialInst = rcm.getMaterialInstanceAt(ri, i)
            val mat = materialInst.material
            if (mat.hasParameter("baseColorFactor")) {
                materialInst.setParameter("baseColorFactor", r, g, b, a)
            } else {
                Log.w(TAG, "Material has no 'baseColorFactor' parameter.")
            }
        }
    }

    private fun resetRenderableColor(entity: Int) {
        val rcm = modelViewer.engine.renderableManager
        if (!rcm.hasComponent(entity)) return
        val ri = rcm.getInstance(entity)
        val count = rcm.getPrimitiveCount(ri)
        for (i in 0 until count) {
            val materialInst = rcm.getMaterialInstanceAt(ri, i)
            val mat = materialInst.material
            if (mat.hasParameter("baseColorFactor")) {
                materialInst.setParameter("baseColorFactor", 1.0f, 1.0f, 1.0f, 1.0f)
            } else {
                Log.w(TAG, "Material has no 'baseColorFactor' parameter.")
            }
        }
    }

    private inner class FrameCallback : Choreographer.FrameCallback {
        private val startTime = System.nanoTime()

        override fun doFrame(frameTimeNanos: Long) {
            choreographer.postFrameCallback(this)

            loadStartFence?.let { fence ->
                val status = fence.wait(Fence.Mode.FLUSH, 0)
                if (status == Fence.FenceStatus.CONDITION_SATISFIED) {
                    val endTime = System.nanoTime()
                    val totalMs = (endTime - loadStartTime) / 1_000_000
                    Log.i(TAG, "Filament backend took $totalMs ms to load the model.")
                    modelViewer.engine.destroyFence(fence)
                    loadStartFence = null

                    applyPreselectedEntities()

                    if (enableCache && cacheManager != null) {
                        notifyCacheChanged();
                    }

                    // OPTIMIZATION: Switch to full quality mode after first frame renders
                    Log.d(TAG, "Model fully loaded - switching to full quality mode")
                    setViewOptions(fastMode = false)

                    // Notify loading completed
                    loadingStateListener?.onLoadingStateChanged(false)

                }
            }

            modelViewer.animator?.apply {
                if (animationCount > 0) {
                    val elapsedTimeSeconds = (frameTimeNanos - startTime) / 1_000_000_000.0
                    applyAnimation(0, elapsedTimeSeconds.toFloat())
                    updateBoneMatrices()
                }
            }

            try {
                modelViewer.render(frameTimeNanos)
            } catch (e: Exception) {
                Log.e(TAG, "Rendering exception: $e")
            }
        }
    }

    private inner class SingleTapListener : GestureDetector.SimpleOnGestureListener() {
        override fun onSingleTapUp(event: MotionEvent): Boolean {
            val x = event.x.toInt()
            val y = textureView.height - event.y.toInt()

            modelViewer.view.pick(x, y, mainExecutor) { result ->
                if (result.renderable == 0) {
                    Log.v(TAG, "No entity picked at ($x, $y)")
                    return@pick
                }
                val entity = result.renderable
                Log.v(TAG, "Picked entity ID: $entity")

                if (selectedEntities.contains(entity)) {
                    resetRenderableColor(entity)
                    selectedEntities.remove(entity)
                    sendSelectedEntitiesToFlutter()
                } else {
                    val entityName = modelViewer.asset?.getName(entity)
                    if (enableCache && entityName != null && cacheManager?.isCached(entityName) == true) {
                        // Remove from cache, reset color, select as normal
                        cacheManager?.removeFromCache(entityName)
                        resetRenderableColor(entity)
                        sendCacheSelectionUpdate()
                        // Optionally select it
                        val color = getEntityColor(entityName)
                        setRenderableColor(entity, color[0], color[1], color[2], color[3])
                        selectedEntities.add(entity)
                        sendSelectedEntitiesToFlutter()
                        return@pick
                    } else {
                        if (enableCache && entityName != null) {
                            cacheManager?.addToCache(entityName)
                            sendCacheSelectionUpdate()
                        }
                    }

                    val color = getEntityColor(entityName)
                    setRenderableColor(entity, color[0], color[1], color[2], color[3])
                    selectedEntities.add(entity)
                }
                sendSelectedEntitiesToFlutter()
            }
            return true
        }
    }

    fun clearCacheAndRestoreSelections() {
        if (enableCache && cacheManager != null) {
            val entitiesToClear = cacheManager!!.cachedEntities.toList()
            cacheManager!!.clearCache()
            // Unhighlight cache entities (but restore color if also selected)
            modelViewer.asset?.getEntities()?.forEach { entity ->
                val name = modelViewer.asset?.getName(entity)
                if (name != null && entitiesToClear.contains(name)) {
                    resetRenderableColor(entity)
                    if (selectedEntities.contains(entity)) {
                        val color = getEntityColor(name)
                        setRenderableColor(entity, color[0], color[1], color[2], color[3])
                    }
                }
            }
            notifyCacheChanged()
        }
    }

    private fun highlightAllCachedEntities() {
        if (enableCache && cacheManager != null) {
            modelViewer.asset?.let { asset ->
                cacheManager?.cachedEntities?.forEach { cachedName ->
                    asset.getEntities().forEach { entity ->
                        val entityName = asset.getName(entity)
                        if (entityName == cachedName && !selectedEntities.contains(entity)) {
                            setRenderableColor(entity, cacheManager!!.cacheColor[0], cacheManager!!.cacheColor[1], cacheManager!!.cacheColor[2], cacheManager!!.cacheColor[3])
                        }
                    }
                }
            }
        }
    }

    fun notifyCacheChanged() {
        highlightAllCachedEntities()
        sendCacheSelectionUpdate()
    }
}