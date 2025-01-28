package com.example.interactive_3d

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
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
import com.google.android.filament.Fence.FenceStatus
import com.google.android.filament.Fence.Mode
import com.google.android.filament.View
import com.google.android.filament.utils.AutomationEngine
import com.google.android.filament.utils.KTX1Loader
import com.google.android.filament.utils.ModelViewer
import java.nio.ByteBuffer
import java.util.concurrent.Executor

/**
 * A custom view that renders a Filament 3D model using a TextureView.
 * It integrates fence logic to measure how long Filament takes to load the model on the GPU.
 */
class ModelView : LinearLayout {

    private val TAG = "ModelView"

    // Replaces SurfaceView with a TextureView for Filament rendering.
    private lateinit var textureView: TextureView

    // Scheduler for frame callbacks.
    private lateinit var choreographer: Choreographer
    private val frameScheduler = FrameCallback()

    // ModelViewer from Filament utils.
    private lateinit var modelViewer: ModelViewer

    // Automation engine (optional features for glTF).
    private val automation = AutomationEngine()

    // Tracks when model loading started, for fence timing.
    private var loadStartTime = 0L
    private var loadStartFence: Fence? = null

    // Viewer content references for advanced usage.
    private val viewerContent = AutomationEngine.ViewerContent()

    // Tap detection for picking entities.
    private lateinit var singleTapDetector: GestureDetector
    private val singleTapListener = SingleTapListener()

    // Keep track of picked entities.
    private var selectedEntities = mutableSetOf<Int>()

    // For .gltf external resource support.
    private val resourceMap = mutableMapOf<String, ByteBuffer>()

    // Main thread executor for pick callbacks, etc.
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { command -> mainHandler.post(command) }

    // Callback interface to report selection changes back to the caller.
    interface SelectionListener {
        fun onSelectionChanged(selectedEntities: List<Map<String, Any>>)
    }
    private var selectionListener: SelectionListener? = null
    fun setSelectionListener(listener: SelectionListener) {
        selectionListener = listener
    }

    //region Constructors
    constructor(context: Context?) : super(context) { init(context) }
    constructor(context: Context?, attrs: AttributeSet?) : super(context, attrs) { init(context) }
    constructor(context: Context?, attrs: AttributeSet?, defStyleAttr: Int)
            : super(context, attrs, defStyleAttr) { init(context) }
    constructor(context: Context?, attrs: AttributeSet?, defStyleAttr: Int, defStyleRes: Int)
            : super(context, attrs, defStyleAttr, defStyleRes) { init(context) }
    //endregion

    @SuppressLint("ClickableViewAccessibility")
    private fun init(context: Context?) {
        // Inflate layout that contains our TextureView (id: main_sv).
        val inflated = LayoutInflater.from(context).inflate(R.layout.custom_view, this, true)
        textureView = inflated.findViewById(R.id.main_sv)

        singleTapDetector = GestureDetector(context, singleTapListener)

        // Prepare Filament's ModelViewer using a TextureView.
        choreographer = Choreographer.getInstance()
        modelViewer = ModelViewer(textureView)
        viewerContent.view = modelViewer.view
        viewerContent.sunlight = modelViewer.light
        viewerContent.lightManager = modelViewer.engine.lightManager
        viewerContent.scene = modelViewer.scene
        viewerContent.renderer = modelViewer.renderer

        // Capture touches for rotating the model and picking.
        textureView.setOnTouchListener { _, event ->
            modelViewer.onTouchEvent(event)
            singleTapDetector.onTouchEvent(event)
            true
        }

        // Start continuous rendering.
        choreographer.postFrameCallback(frameScheduler)

        // Activity lifecycle handling to pause/resume rendering.
        (context as? Activity)?.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(a: Activity, b: Bundle?) {}
            override fun onActivityStarted(a: Activity) {}
            override fun onActivityResumed(a: Activity) {
                choreographer.postFrameCallback(frameScheduler)
            }
            override fun onActivityPaused(a: Activity) {
                choreographer.removeFrameCallback(frameScheduler)
            }
            override fun onActivityStopped(a: Activity) {}
            override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
            override fun onActivityDestroyed(a: Activity) {
                choreographer.removeFrameCallback(frameScheduler)
                 modelViewer.destroyModel()
            }
        })
    }

    /**
     * Load a 3D model (GLB or GLTF). We create a fence to measure GPU load completion time.
     */
    fun setModel(buffer: ByteBuffer, fileName: String, resources: Map<String, ByteArray>) {
        resources.forEach { (key, value) ->
            resourceMap[key] = ByteBuffer.wrap(value)
        }

        if (fileName.endsWith(".gltf", ignoreCase = true)) {
            modelViewer.loadModelGltfAsync(buffer) { resourcePath ->
                resourceMap[resourcePath] ?: run {
                    Log.e(TAG, "Missing resource: $resourcePath")
                    ByteBuffer.allocate(0) // Return empty buffer if not found.
                }
            }
            Log.d(TAG, "Loaded GLTF model: $fileName")
        } else if (fileName.endsWith(".glb", ignoreCase = true)) {
            modelViewer.loadModelGlb(buffer)
            Log.d(TAG, "Loaded GLB model: $fileName")
        } else {
            Log.e(TAG, "Unsupported model format: $fileName")
            return
        }

        // Transform model to fit the view if auto-scale is enabled.
        if (automation.viewerOptions.autoScaleEnabled) {
            modelViewer.transformToUnitCube()
        } else {
            modelViewer.clearRootTransform()
        }

        // Start timing the backend load with a fence.
        loadStartTime = System.nanoTime()
        loadStartFence = modelViewer.engine.createFence()
    }

    /**
     * Load skybox and IBL from KTX buffers.
     */
    fun setLights(skyBox: ByteBuffer, indirectLight: ByteBuffer) {
        val engine = modelViewer.engine
        val scene = modelViewer.scene
        scene.indirectLight = KTX1Loader.createIndirectLight(engine, indirectLight)
        scene.indirectLight?.intensity = 30_000.0f
        viewerContent.indirectLight = scene.indirectLight
        scene.skybox = KTX1Loader.createSkybox(engine, skyBox)
    }

    /**
     * Configure post-processing and rendering quality.
     */
    fun setViewOptions() {
        val view = modelViewer.view
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

    /**
     * An optional cleanup method if you want to destroy the model from outside.
     */
    fun destroy() {
        modelViewer.destroyModel()
        automation.stopRunning()
    }

    /**
     * Our frame callback that keeps rendering and checks if the fence has passed.
     */
    private inner class FrameCallback : Choreographer.FrameCallback {
        private val startTime = System.nanoTime()

        override fun doFrame(frameTimeNanos: Long) {
            choreographer.postFrameCallback(this)

            // If we have a fence, wait(FLUSH, 0) to see if the GPU has finished loading.
            loadStartFence?.let { fence ->
                val status = fence.wait(Mode.FLUSH, 0)
                if (status == FenceStatus.CONDITION_SATISFIED) {
                    val endTime = System.nanoTime()
                    val totalMs = (endTime - loadStartTime) / 1_000_000
                    Log.i(TAG, "Filament backend took $totalMs ms to load the model.")
                    modelViewer.engine.destroyFence(fence)
                    loadStartFence = null
                }
            }

            // Animate model if it has animations.
            modelViewer.animator?.apply {
                if (animationCount > 0) {
                    val elapsedTimeSeconds = (frameTimeNanos - startTime) / 1_000_000_000.0
                    applyAnimation(0, elapsedTimeSeconds.toFloat())
                    updateBoneMatrices()
                }
            }

            // Render the frame.
            try {
                modelViewer.render(frameTimeNanos)
            } catch (e: Exception) {
                Log.e(TAG, "Rendering exception: $e")
            }
        }
    }

    /**
     * Single-tap listener to pick an entity on the model.
     */
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
                } else {
                    setRenderableColor(entity, 1.0f, 0.0f, 0.0f, 1.0f)
                    selectedEntities.add(entity)
                }
                sendSelectedEntitiesToFlutter()
            }
            return super.onSingleTapUp(event)
        }
    }

    /**
     * Notify Flutter about current selections.
     */
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
}
