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
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.widget.LinearLayout
import com.google.android.filament.View
import com.google.android.filament.utils.AutomationEngine
import com.google.android.filament.utils.KTX1Loader
import com.google.android.filament.utils.ModelViewer
import java.nio.ByteBuffer
import java.util.concurrent.Executor

// Custom view for 3D model rendering
class ModelView : LinearLayout {

    val TAG = "ModelView"

    // The surface view for rendering the 3D model
    private lateinit var surfaceView: SurfaceView
    // The choreographer for scheduling frame callbacks
    private lateinit var choreographer: Choreographer
    // The frame scheduler for rendering the 3D model
    private val frameScheduler = FrameCallback()
    // The model viewer for rendering the 3D model
    private lateinit var modelViewer: ModelViewer
    // The automation engine for running automation scripts
    private val automation = AutomationEngine()
    // The viewer content for the model viewer
    private val viewerContent = AutomationEngine.ViewerContent()
    // The single-tap detector for picking entities
    private lateinit var singleTapDetector: GestureDetector
    private val singleTapListener = SingleTapListener()
    // The set of selected entities
    private var selectedEntities = mutableSetOf<Int>()
    // The map of resources only for .gltf models
    private val resourceMap = mutableMapOf<String, ByteBuffer>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { command ->
        mainHandler.post(command)
    }

    // Add a callback interface
    interface SelectionListener {
        fun onSelectionChanged(selectedEntities: List<Map<String, Any>>)
    }

    // Add a listener variable
    private var selectionListener: SelectionListener? = null

    // Method to set the listener
    fun setSelectionListener(listener: SelectionListener) {
        this.selectionListener = listener
    }


    constructor(context: Context?) : super(context) {
        init(context)
    }

    constructor(context: Context?, attrs: AttributeSet?) : super(context, attrs) {
        init(context)
    }

    constructor(context: Context?, attrs: AttributeSet?, defStyleAttr: Int) : super(
        context,
        attrs,
        defStyleAttr
    ) {
        init(context)
    }

    constructor(
        context: Context?,
        attrs: AttributeSet?,
        defStyleAttr: Int,
        defStyleRes: Int
    ) : super(context, attrs, defStyleAttr, defStyleRes) {
        init(context)
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun init(context: Context?) {

        // Inflate the custom view layout
        val inflated = LayoutInflater.from(context).inflate(R.layout.custom_view, this, true)
        surfaceView = inflated.findViewById(R.id.main_sv);

        // Set the touch listener for the surface view
        surfaceView.setOnTouchListener { _, event ->
            modelViewer.onTouchEvent(event)
            singleTapDetector.onTouchEvent(event)
            true
        }

        singleTapDetector = GestureDetector(context, singleTapListener)

        choreographer = Choreographer.getInstance()
        modelViewer = ModelViewer(surfaceView)
        viewerContent.view = modelViewer.view
        viewerContent.sunlight = modelViewer.light
        viewerContent.lightManager = modelViewer.engine.lightManager
        viewerContent.scene = modelViewer.scene
        viewerContent.renderer = modelViewer.renderer

        //callbacks
        surfaceView.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                Log.d(
                    TAG,
                    "SurfaceCallback: 1 : surfaceCreated: Let ModelViewer handle attaching internally."
                )
            }

            override fun surfaceChanged(
                holder: SurfaceHolder,
                format: Int,
                width: Int,
                height: Int
            ) {
                Log.d(
                    TAG,
                    "SurfaceCallback: 2 : surfaceChanged: updating viewport to ($width, $height)"
                )
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                Log.d(
                    TAG,
                    "SurfaceCallback: 3 : surfaceDestroyed: Let ModelViewer handle detaching internally."
                )
            }
        })

        choreographer.postFrameCallback(frameScheduler)

        (context as Activity).registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(p0: Activity, p1: Bundle?) {
                Log.e(TAG, "onActivityCreated: ")
            }

            override fun onActivityStarted(p0: Activity) {
                Log.e(TAG, "onActivityStarted: ")
            }

            override fun onActivityResumed(p0: Activity) {
                Log.e(TAG, "onActivityResumed: ")
                choreographer.postFrameCallback(frameScheduler)
            }

            override fun onActivityPaused(p0: Activity) {
                Log.e(TAG, "onActivityPaused: ")
                choreographer.removeFrameCallback(frameScheduler)
            }

            override fun onActivityStopped(p0: Activity) {
                Log.e(TAG, "onActivityStopped: ")
            }

            override fun onActivitySaveInstanceState(p0: Activity, p1: Bundle) {
                Log.e(TAG, "onActivitySaveInstanceState: ")
            }

            override fun onActivityDestroyed(p0: Activity) {
                Log.e(TAG, "onActivityDestroyed: ")
                choreographer.removeFrameCallback(frameScheduler)
                modelViewer.destroyModel()
            }
        })
    }

    // Load the model from the given buffer
    fun setModel(buffer: ByteBuffer, fileName: String, resources: Map<String, ByteArray>) {
        resources.forEach { (key, value) ->
            resourceMap[key] = ByteBuffer.wrap(value)
        }

        if (fileName.endsWith(".gltf", ignoreCase = true)) {
            modelViewer.loadModelGltfAsync(buffer) { resourcePath ->
                (resourceMap[resourcePath] ?: run {
                    Log.e(TAG, "Missing resource: $resourcePath")
                    null
                })!!
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
    }

    // Load the lights from the given buffers
    fun setLights(skyBox: ByteBuffer, indirectLight: ByteBuffer) {
        val engine = modelViewer.engine
        val scene = modelViewer.scene
        scene.indirectLight = KTX1Loader.createIndirectLight(engine, indirectLight)
        scene.indirectLight!!.intensity = 30_000.0f
        viewerContent.indirectLight = scene.indirectLight
        scene.skybox = KTX1Loader.createSkybox(engine, skyBox)
    }

    // Set the view options for the model viewer
    fun setViewOptions() {
        val view = modelViewer.view

        // Set render quality options
        view.renderQuality = view.renderQuality.apply {
            hdrColorBuffer = View.QualityLevel.MEDIUM
        }

        // Enable dynamic resolution
        view.dynamicResolutionOptions = view.dynamicResolutionOptions.apply {
            enabled = true
            quality = View.QualityLevel.MEDIUM
        }

        // Enable MSAA
        view.multiSampleAntiAliasingOptions = view.multiSampleAntiAliasingOptions.apply {
            enabled = true
        }

        // Enable FXAA
        view.antiAliasing = View.AntiAliasing.FXAA

        // Enable ambient occlusion
        view.ambientOcclusionOptions = view.ambientOcclusionOptions.apply {
            enabled = true
        }

        // Enable bloom
        view.bloomOptions = view.bloomOptions.apply {
            enabled = true
        }
    }

    fun destory() {
        modelViewer.destroyModel()
        automation.stopRunning()
    }

    private fun sendSelectedEntitiesToFlutter() {
        val asset = modelViewer.asset ?: return
        val names = mutableListOf<Map<String, Any>>()

        for (entity in selectedEntities) {
            val name = asset.getName(entity) ?: "Unnamed Entity"
            val id = entity.toLong()
            names.add(mapOf("id" to id, "name" to name))
        }
        selectionListener?.onSelectionChanged(names)
    }


    inner class FrameCallback : Choreographer.FrameCallback {
        private val startTime = System.nanoTime()
        override fun doFrame(frameTimeNanos: Long) {
            choreographer.postFrameCallback(this)

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
                Log.e(TAG, "doFrame: Exception")
            }
        }
    }

    // Single-tap listener for picking
    inner class SingleTapListener : GestureDetector.SimpleOnGestureListener() {
        override fun onSingleTapUp(event: MotionEvent): Boolean {
            val x = event.x.toInt()
            val y = surfaceView.height - event.y.toInt()

            modelViewer.view.pick(x, y, mainExecutor) { result ->
                if (result.renderable == 0) {
                    Log.v(TAG, "No entity picked at ($x, $y)")
                    return@pick
                }

                val renderable = result.renderable
                Log.v(TAG, "Picked entity ID: $renderable")

                if (selectedEntities.contains(renderable)) {
                    resetRenderableColor(renderable)
                    selectedEntities.remove(renderable)
                } else {
                    setRenderableColor(renderable, 1.0f, 0.0f, 0.0f, 1.0f) // Red color
                    selectedEntities.add(renderable)
                }
                sendSelectedEntitiesToFlutter()
            }
            return super.onSingleTapUp(event)
        }
    }

    // Set the color of the renderable
    private fun setRenderableColor(renderable: Int, r: Float, g: Float, b: Float, a: Float) {
        val engine = modelViewer.engine
        val rcm = engine.renderableManager

        if (rcm.hasComponent(renderable)) {
            val ri = rcm.getInstance(renderable)
            val primitiveCount = rcm.getPrimitiveCount(ri)
            for (i in 0 until primitiveCount) {
                val mi = rcm.getMaterialInstanceAt(ri, i)
                val material = mi.material
                if (material.hasParameter("baseColorFactor")) {
                    mi.setParameter("baseColorFactor", r, g, b, a)
                } else {
                    Log.w(TAG, "Material does not have parameter 'baseColorFactor'")
                }
            }
        }
    }

    // Reset the color of the renderable
    private fun resetRenderableColor(renderable: Int) {
        val engine = modelViewer.engine
        val rcm = engine.renderableManager

        if (rcm.hasComponent(renderable)) {
            val ri = rcm.getInstance(renderable)
            val primitiveCount = rcm.getPrimitiveCount(ri)
            for (i in 0 until primitiveCount) {
                val mi = rcm.getMaterialInstanceAt(ri, i)
                val material = mi.material
                if (material.hasParameter("baseColorFactor")) {
                    mi.setParameter("baseColorFactor", 1.0f, 1.0f, 1.0f, 1.0f)
                } else {
                    Log.w(TAG, "Material does not have parameter 'baseColorFactor'")
                }
            }
        }
    }
}
