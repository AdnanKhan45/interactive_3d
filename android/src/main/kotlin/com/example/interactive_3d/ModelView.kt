// ModelView.kt
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

class ModelView : LinearLayout {

    private val TAG = "ModelView"

    private lateinit var textureView: TextureView
    private lateinit var choreographer: Choreographer
    private val frameScheduler = FrameCallback()
    private lateinit var modelViewer: ModelViewer
    private val automation = AutomationEngine()
    private var loadStartTime = 0L
    private var loadStartFence: Fence? = null
    private val viewerContent = AutomationEngine.ViewerContent()
    private lateinit var singleTapDetector: GestureDetector
    private val singleTapListener = SingleTapListener()
    private val selectedEntities = mutableSetOf<Int>()
    private val resourceMap = mutableMapOf<String, ByteBuffer>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { command -> mainHandler.post(command) }
    private var pendingPreselectedEntities: List<String>? = null
    private var modelLoaded = false
    private var selectionColor: FloatArray? = null // Store RGBA as [r, g, b, a]

    interface SelectionListener {
        fun onSelectionChanged(selectedEntities: List<Map<String, Any>>)
    }
    private var selectionListener: SelectionListener? = null
    fun setSelectionListener(listener: SelectionListener) {
        selectionListener = listener
    }

    constructor(context: Context?) : super(context) { init(context) }
    constructor(context: Context?, attrs: AttributeSet?) : super(context, attrs) { init(context) }
    constructor(context: Context?, attrs: AttributeSet?, defStyleAttr: Int) : super(context, attrs, defStyleAttr) { init(context) }
    constructor(context: Context?, attrs: AttributeSet?, defStyleAttr: Int, defStyleRes: Int) : super(context, attrs, defStyleAttr, defStyleRes) { init(context) }

    @SuppressLint("ClickableViewAccessibility")
    private fun init(context: Context?) {
        val inflated = LayoutInflater.from(context).inflate(R.layout.custom_view, this, true)
        textureView = inflated.findViewById(R.id.main_sv)

        singleTapDetector = GestureDetector(context, singleTapListener)

        choreographer = Choreographer.getInstance()
        modelViewer = ModelViewer(textureView)
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

        (context as? Activity)?.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
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
                modelViewer.destroyModel()
            }


        })
    }

    fun setCameraZoomLevel(zoom: Float) {
        // Ensure the textureView dimensions are available.
        val width = textureView.width.takeIf { it != 0 } ?: return
        val height = textureView.height.takeIf { it != 0 } ?: return

        if (textureView.width == 0 || textureView.height == 0) {
            Log.w(TAG, "Cannot set zoom: textureView dimensions are zero.")
            return
        }


        val camera = modelViewer.camera
        val aspect = width.toDouble() / height.toDouble()
        val near = 0.1
        val far = 100.0

        // Define a default vertical field-of-view (in degrees)
        val defaultFov = 50.0
        // Adjust the FOV based on the zoom factor:
        // Zoom = 1 returns the default FOV,
        // Zoom > 1 returns a smaller FOV (zoom in),
        // Zoom < 1 returns a larger FOV (zoom out)
        val newFov = defaultFov / zoom

        // Use the newFov, aspect, near, far, and FOV direction.
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
     * Load a 3D model (GLB or GLTF) with optional preselected entities and selection color.
     */
    fun setModel(
        buffer: ByteBuffer,
        fileName: String,
        resources: Map<String, ByteArray>,
        preselectedEntities: List<String>?,
        selectionColor: List<Double>?
    ) {
        this.pendingPreselectedEntities = preselectedEntities
        // Convert selectionColor to FloatArray or use default green
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
        setModel(buffer, fileName, resources)
    }

    /**
     * Load a 3D model (GLB or GLTF).
     */
    private fun setModel(buffer: ByteBuffer, fileName: String, resources: Map<String, ByteArray>) {
        modelLoaded = false
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
            Log.d(TAG, "Loaded GLTF model: $fileName")
        } else if (fileName.endsWith(".glb", ignoreCase = true)) {
            modelViewer.loadModelGlb(buffer)
            Log.d(TAG, "Loaded GLB model: $fileName")
        } else {
            Log.e(TAG, "Unsupported model format: $fileName")
            return
        }

        if (automation.viewerOptions.autoScaleEnabled) {
            modelViewer.transformToUnitCube()
        } else {
            modelViewer.clearRootTransform()
        }

        loadStartTime = System.nanoTime()
        loadStartFence = modelViewer.engine.createFence()
        modelLoaded = true
    }

    fun setLights(skyBox: ByteBuffer, indirectLight: ByteBuffer) {
        val engine = modelViewer.engine
        val scene = modelViewer.scene
        scene.indirectLight = KTX1Loader.createIndirectLight(engine, indirectLight)
        scene.indirectLight?.intensity = 30_000.0f
        viewerContent.indirectLight = scene.indirectLight
        scene.skybox = KTX1Loader.createSkybox(engine, skyBox)
    }

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

    fun destroy() {
        modelViewer.destroyModel()
        automation.stopRunning()
    }

    private fun applyPreselectedEntities() {
        if (pendingPreselectedEntities == null || !modelLoaded) return

        pendingPreselectedEntities?.forEach { name ->
            modelViewer.asset?.getEntities()?.forEach { entity ->
                val entityName = modelViewer.asset?.getName(entity)
                if (name == entityName && entity !in selectedEntities) {
                    val color = selectionColor ?: floatArrayOf(0.0f, 1.0f, 0.0f, 1.0f)
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
                } else {
                    val color = selectionColor ?: floatArrayOf(0.0f, 1.0f, 0.0f, 1.0f)
                    setRenderableColor(entity, color[0], color[1], color[2], color[3])
                    selectedEntities.add(entity)
                }
                sendSelectedEntitiesToFlutter()
            }
            return true
        }
    }
}