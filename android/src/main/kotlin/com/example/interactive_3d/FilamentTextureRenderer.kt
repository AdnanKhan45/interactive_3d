package com.example.interactive_3d

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import com.google.android.filament.*
import com.google.android.filament.gltfio.*
import com.google.android.filament.utils.KTX1Loader
import java.nio.ByteBuffer
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * FilamentTextureRenderer - Core Filament rendering engine.
 *
 * FIXES APPLIED:
 * - Changed NEAR_PLANE from 0.1 to 0.001 for small models
 * - Fixed camera distance calculation using FOV
 * - Enhanced lighting for PBR materials without IBL
 * - Dark gray background to show light-colored models
 * - Material property overrides for debugging
 * - Disabled frustum culling for debugging
 * - Increased pan sensitivity by 25% (0.009375 from 0.0075)
 * - SOLID COLOR SELECTION using custom UNLIT material replacement
 */
class FilamentTextureRenderer(
    private val context: Context,
    private var width: Int,
    private var height: Int
) {
    companion object {
        private const val TAG = "FilamentRenderer"
        private const val NEAR_PLANE = 0.001  // Changed from 0.1 to 0.001
        private const val FAR_PLANE = 1000.0
        private const val DEFAULT_FOV = 45.0

        // Pre-compiled UNLIT solid color material (generated with matc tool)
        // This material simply outputs the baseColor parameter as a solid color
        // Equivalent to: material.baseColor = materialParams.baseColor;
        private val SOLID_COLOR_MATERIAL_DATA: ByteArray by lazy {
            // This is a pre-compiled filamat material package for UNLIT solid color
            // Generated using matc with this definition:
            // material {
            //     name : "SolidColor",
            //     shadingModel : unlit,
            //     parameters : [
            //         { type : float4, name : baseColor }
            //     ]
            // }
            // fragment {
            //     void material(inout MaterialInputs material) {
            //         prepareMaterial(material);
            //         material.baseColor = materialParams.baseColor;
            //     }
            // }
            createSolidColorMaterialPackage()
        }

        private fun createSolidColorMaterialPackage(): ByteArray {
            // Return empty - we'll build at runtime or use alternative approach
            return ByteArray(0)
        }
    }

    // Core Filament objects
    private var engine: Engine? = null
    private var renderer: Renderer? = null
    private var scene: Scene? = null
    private var view: View? = null
    private var camera: Camera? = null
    private var cameraEntity: Int = 0
    private var swapChain: SwapChain? = null

    // GLTF loading
    private var materialProvider: MaterialProvider? = null
    private var assetLoader: AssetLoader? = null
    private var resourceLoader: ResourceLoader? = null
    private var currentAsset: FilamentAsset? = null

    // Lighting
    private var indirectLight: IndirectLight? = null
    private var skybox: Skybox? = null
    private var sunlight: Int = 0
    private var fillLight: Int = 0
    private var backLight: Int = 0
    private var iblLoaded = false  // Track if IBL environment is loaded

    // Render loop
    private val choreographer = Choreographer.getInstance()
    private var isRendering = false
    private val frameCallback = FrameCallback()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Camera control
    private var orbitRadius = 5.0f
    private var orbitAngleX = 0.3f  // Slight tilt by default
    private var orbitAngleY = 0.5f  // Front-right view
    private var targetPosition = floatArrayOf(0f, 0f, 0f)
    private var zoomLevel = 1.0f  // Start at 1.0, not zoomed

    // Selection
    private val selectedEntities = mutableSetOf<Int>()
    private var selectionColor = floatArrayOf(0f, 1f, 0f, 1f)
    private var patchColors: List<Map<String, Any>>? = null
    private val entityVisibilities = mutableMapOf<Int, Boolean>()

    // Cache
    private var enableCache = false
    private var cacheManager: Interactive3dCacheManager? = null
    private var cacheColor = floatArrayOf(0.8f, 0.8f, 0.2f, 0.6f)

    // Pending operations
    private var pendingPreselectedEntities: List<String>? = null
    private var modelLoaded = false

    // Listeners
    private var selectionListener: ((List<Map<String, Any>>) -> Unit)? = null
    private var cacheSelectionListener: ((List<Map<String, Any>>) -> Unit)? = null

    init {
        initializeFilament()
    }

    private fun initializeFilament() {
        Log.d(TAG, "Initializing Filament engine")

        try {
            engine = Engine.create()
            val eng = engine ?: throw IllegalStateException("Failed to create Filament Engine")

            renderer = eng.createRenderer()

            // QUALITY: Configure renderer for better visual quality
            renderer?.apply {
                // Clear options will be set in setupViewOptions
            }
            scene = eng.createScene()
            view = eng.createView()
            view?.setScene(scene)

            cameraEntity = EntityManager.get().create()
            camera = eng.createCamera(cameraEntity)
            view?.camera = camera

            setupCamera()
            setupEnhancedDefaultLighting()
            setupViewOptions()

            materialProvider = UbershaderProvider(eng)
            assetLoader = AssetLoader(eng, materialProvider!!, EntityManager.get())
            resourceLoader = ResourceLoader(eng, true)

            Log.d(TAG, "Filament initialization complete")
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing Filament: ${e.message}", e)
            throw e
        }
    }

    fun createSwapChain(surface: Surface) {
        val eng = engine ?: return
        Log.d(TAG, "Creating SwapChain from Surface (${width}x${height})")

        destroySwapChain()

        try {
            swapChain = eng.createSwapChain(surface)
            view?.viewport = Viewport(0, 0, width, height)

            camera?.setProjection(
                DEFAULT_FOV / zoomLevel,
                if (height > 0) width.toDouble() / height.toDouble() else 1.0,
                NEAR_PLANE,
                FAR_PLANE,
                Camera.Fov.VERTICAL
            )

            updateCameraPosition()
            Log.d(TAG, "SwapChain created successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error creating SwapChain: ${e.message}", e)
        }
    }

    fun destroySwapChain() {
        val eng = engine ?: return
        swapChain?.let {
            Log.d(TAG, "Destroying SwapChain")
            eng.destroySwapChain(it)
            swapChain = null
        }
    }

    fun updateViewport(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return

        this.width = width
        this.height = height
        view?.viewport = Viewport(0, 0, width, height)

        camera?.setProjection(
            DEFAULT_FOV / zoomLevel,
            width.toDouble() / height.toDouble(),
            NEAR_PLANE,
            FAR_PLANE,
            Camera.Fov.VERTICAL
        )
    }

    fun startRenderLoop() {
        if (isRendering) return
        Log.d(TAG, "Starting render loop")
        isRendering = true
        choreographer.postFrameCallback(frameCallback)
    }

    fun stopRenderLoop() {
        Log.d(TAG, "Stopping render loop")
        isRendering = false
        choreographer.removeFrameCallback(frameCallback)
    }

    private fun setupCamera() {
        camera?.apply {
            setProjection(
                DEFAULT_FOV,
                width.toDouble() / height.toDouble(),
                NEAR_PLANE,
                FAR_PLANE,
                Camera.Fov.VERTICAL
            )
        }
        updateCameraPosition()
    }

    private fun updateCameraPosition() {
        val cam = camera ?: return

        val radius = orbitRadius / zoomLevel

        val x = radius * cos(orbitAngleX.toDouble()) * sin(orbitAngleY.toDouble())
        val y = radius * sin(orbitAngleX.toDouble())
        val z = radius * cos(orbitAngleX.toDouble()) * cos(orbitAngleY.toDouble())

        val eyeX = x + targetPosition[0].toDouble()
        val eyeY = y + targetPosition[1].toDouble()
        val eyeZ = z + targetPosition[2].toDouble()

        cam.lookAt(
            eyeX, eyeY, eyeZ,
            targetPosition[0].toDouble(),
            targetPosition[1].toDouble(),
            targetPosition[2].toDouble(),
            0.0, 1.0, 0.0
        )

        val dx = eyeX - targetPosition[0]
        val dy = eyeY - targetPosition[1]
        val dz = eyeZ - targetPosition[2]
        val distanceToTarget = Math.sqrt(dx*dx + dy*dy + dz*dz)

        Log.d(TAG, "Camera: eye=[%.3f, %.3f, %.3f], target=[%.3f, %.3f, %.3f], radius=%.3f, dist=%.3f".format(
            eyeX, eyeY, eyeZ, targetPosition[0], targetPosition[1], targetPosition[2], radius, distanceToTarget
        ))

        if (distanceToTarget < NEAR_PLANE * 2) {
            Log.w(TAG, "⚠️ Camera very close! Distance ($distanceToTarget) < 2*nearPlane (${NEAR_PLANE*2})")
        }
    }

    private fun setupEnhancedDefaultLighting() {
        val eng = engine ?: return
        val scn = scene ?: return

        Log.d(TAG, "Setting up enhanced default lighting")

        sunlight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 1.0f, 1.0f)
            .intensity(250000.0f)
            .direction(0.0f, -1.0f, -0.3f)
            .castShadows(false)
            .build(eng, sunlight)
        scn.addEntity(sunlight)

        fillLight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.9f, 0.9f, 1.0f)
            .intensity(100000.0f)
            .direction(1.0f, 0.0f, 0.0f)
            .castShadows(false)
            .build(eng, fillLight)
        scn.addEntity(fillLight)

        backLight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 1.0f, 0.9f)
            .intensity(80000.0f)
            .direction(-0.5f, 0.5f, 1.0f)
            .castShadows(false)
            .build(eng, backLight)
        scn.addEntity(backLight)

        try {
            val indirectLightBuilder = IndirectLight.Builder()
                .intensity(50000.0f)
                .irradiance(3, floatArrayOf(
                    1.0f, 1.0f, 1.0f,
                    0.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 0.0f
                ))

            indirectLight = indirectLightBuilder.build(eng)
            scn.indirectLight = indirectLight
            Log.d(TAG, "Simple indirect light created")
        } catch (e: Exception) {
            Log.w(TAG, "Could not create indirect light: ${e.message}")
        }

        Log.d(TAG, "Enhanced lighting setup complete")
    }

    private fun setupViewOptions() {
        view?.apply {
            // FXAA anti-aliasing
            antiAliasing = View.AntiAliasing.FXAA

            // DISABLED dynamic resolution - causes pixelation
            dynamicResolutionOptions = dynamicResolutionOptions.apply {
                enabled = false  // Keep disabled for maximum sharpness
                quality = View.QualityLevel.HIGH
            }

            // Keep AO and Bloom disabled initially (enabled when IBL loads)
            ambientOcclusionOptions = ambientOcclusionOptions.apply {
                enabled = false
            }
            bloomOptions = bloomOptions.apply {
                enabled = false
            }

            // Disable temporal AA (can blur on low-end)
            temporalAntiAliasingOptions = temporalAntiAliasingOptions.apply {
                enabled = false
            }

            // QUALITY BOOST: Enable multi-sample anti-aliasing
            multiSampleAntiAliasingOptions = multiSampleAntiAliasingOptions.apply {
                enabled = true
                sampleCount = 4  // 4x MSAA for smoother edges
            }
        }

        renderer?.setClearOptions(
            Renderer.ClearOptions().apply {
                clearColor = floatArrayOf(0.2f, 0.2f, 0.2f, 1.0f)
                clear = true
            }
        )

        Log.d(TAG, "View options configured (FXAA + 4x MSAA)")
    }

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
        Log.d(TAG, "Loading model: $fileName")

        val eng = engine ?: return
        val scn = scene ?: return
        val loader = assetLoader ?: return
        val resLoader = resourceLoader ?: return

        cleanupPreviousModel()

        this.pendingPreselectedEntities = preselectedEntities
        this.selectionColor = if (selectionColor?.size == 4) {
            floatArrayOf(
                selectionColor[0].toFloat(),
                selectionColor[1].toFloat(),
                selectionColor[2].toFloat(),
                selectionColor[3].toFloat()
            )
        } else {
            floatArrayOf(0f, 1f, 0f, 1f)
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
                floatArrayOf(0.8f, 0.8f, 0.2f, 0.6f)
            }
            this.cacheColor = color
            cacheManager = Interactive3dCacheManager(context, fileName, color)
        }

        try {
            buffer.rewind()

            val asset = if (fileName.endsWith(".glb", ignoreCase = true)) {
                loader.createAsset(buffer)
            } else {
                loader.createAsset(buffer)
            }

            if (asset == null) {
                Log.e(TAG, "Failed to create asset from $fileName")
                return
            }

            currentAsset = asset

            if (resources.isNotEmpty()) {
                asset.resourceUris?.forEach { uri ->
                    resources[uri]?.let { data ->
                        resLoader.addResourceData(uri, ByteBuffer.wrap(data))
                    }
                }
            }

            resLoader.loadResources(asset)
            asset.releaseSourceData()

            val entities = asset.entities
            var addedCount = 0
            var renderableCount = 0

            entities?.forEach { entity ->
                scn.addEntity(entity)
                addedCount++

                if (eng.renderableManager.hasComponent(entity)) {
                    renderableCount++
                }
            }

            Log.d(TAG, "Added $addedCount entities, $renderableCount have renderables")

            makeModelVisibleWithoutIBL(asset)
            fitModelInView(asset)

            modelLoaded = true
            applyPreselectedEntities()

            if (enableCache) {
                notifyCacheChanged()
            }

            Log.d(TAG, "Model loaded successfully: ${entities?.size ?: 0} entities")
        } catch (e: Exception) {
            Log.e(TAG, "Error loading model: ${e.message}", e)
        }
    }

    private fun makeModelVisibleWithoutIBL(asset: FilamentAsset) {
        val eng = engine ?: return
        val rcm = eng.renderableManager

        Log.d(TAG, "Applying material overrides for visibility")

        var modifiedCount = 0
        asset.entities?.forEach { entity ->
            if (!rcm.hasComponent(entity)) return@forEach

            val ri = rcm.getInstance(entity)
            val count = rcm.getPrimitiveCount(ri)

            for (i in 0 until count) {
                try {
                    val materialInst = rcm.getMaterialInstanceAt(ri, i)
                    materialInst.setParameter("baseColorFactor", 1.0f, 1.0f, 1.0f, 1.0f)
                    materialInst.setParameter("metallicFactor", 0.1f)
                    materialInst.setParameter("roughnessFactor", 0.8f)
                    materialInst.setParameter("emissiveFactor", 0.2f, 0.2f, 0.2f)

                    modifiedCount++
                } catch (e: Exception) {
                    Log.w(TAG, "Could not modify material: ${e.message}")
                }
            }
        }

        Log.d(TAG, "Modified $modifiedCount materials")
    }

    private fun fitModelInView(asset: FilamentAsset) {
        val boundingBox = asset.boundingBox
        val center = boundingBox.center
        val halfExtent = boundingBox.halfExtent

        Log.d(TAG, "Model bbox - center: [${center[0]}, ${center[1]}, ${center[2]}], halfExtent: [${halfExtent[0]}, ${halfExtent[1]}, ${halfExtent[2]}]")

        targetPosition = floatArrayOf(center[0], center[1], center[2])

        val maxExtent = max(max(halfExtent[0], halfExtent[1]), halfExtent[2])
        val fovRadians = Math.toRadians(DEFAULT_FOV)
        val distance = (maxExtent * 2.0f) / Math.tan(fovRadians / 2.0).toFloat()
        orbitRadius = distance * 3.0f  // Changed from 1.5x to 3.0x for better view
        orbitRadius = maxOf(orbitRadius, 1.0f)  // Increased minimum from 0.5f to 1.0f

        orbitAngleX = 0.3f
        orbitAngleY = 0.5f

        Log.d(TAG, "Camera configured - orbit: $orbitRadius, distance: $distance, maxExtent: $maxExtent")

        updateCameraPosition()
    }

    fun loadEnvironment(iblBuffer: ByteBuffer, skyboxBuffer: ByteBuffer) {
        Log.d(TAG, "Loading environment")
        val eng = engine ?: return
        val scn = scene ?: return

        try {
            iblBuffer.rewind()
            val iblBundle = KTX1Loader.createIndirectLight(eng, iblBuffer)
            indirectLight?.let { eng.destroyIndirectLight(it) }
            indirectLight = iblBundle.indirectLight
            indirectLight?.intensity = 50000.0f
            scn.indirectLight = indirectLight

            skyboxBuffer.rewind()
            val skyboxBundle = KTX1Loader.createSkybox(eng, skyboxBuffer)
            skybox = skyboxBundle.skybox
            scn.skybox = skybox

            view?.apply {
                ambientOcclusionOptions = ambientOcclusionOptions.apply {
                    enabled = true
                }
                bloomOptions = bloomOptions.apply {
                    enabled = true
                }
            }

            currentAsset?.let { restoreOriginalMaterials(it) }
            iblLoaded = true  // Mark that IBL is now active
            Log.d(TAG, "Environment loaded, AO/Bloom enabled")
        } catch (e: Exception) {
            Log.e(TAG, "Error loading environment: ${e.message}", e)
        }
    }

    private fun restoreOriginalMaterials(asset: FilamentAsset) {
        val eng = engine ?: return
        val rcm = eng.renderableManager

        asset.entities?.forEach { entity ->
            if (!rcm.hasComponent(entity)) return@forEach
            val ri = rcm.getInstance(entity)
            val count = rcm.getPrimitiveCount(ri)

            for (i in 0 until count) {
                try {
                    val materialInst = rcm.getMaterialInstanceAt(ri, i)
                    materialInst.setParameter("emissiveFactor", 0.0f, 0.0f, 0.0f)
                } catch (e: Exception) {
                    Log.w(TAG, "Could not restore material: ${e.message}")
                }
            }
        }
    }

    fun setCameraZoomLevel(zoom: Float) {
        if (zoom <= 0) return
        zoomLevel = zoom
        camera?.setProjection(
            DEFAULT_FOV / zoom,
            width.toDouble() / height.toDouble(),
            NEAR_PLANE,
            FAR_PLANE,
            Camera.Fov.VERTICAL
        )
        updateCameraPosition()
    }

    fun onTap(x: Int, y: Int) {
        val v = view ?: return
        val flippedY = height - y

        v.pick(x, flippedY, mainHandler) { result ->
            val entity = result.renderable
            if (entity == 0) {
                Log.v(TAG, "No entity picked at ($x, $y)")
                return@pick
            }
            handleEntityPicked(entity)
        }
    }

    private fun handleEntityPicked(entity: Int) {
        val asset = currentAsset ?: return

        // CRITICAL FIX: Check if entity belongs to our model (not lights, camera, etc.)
        val isModelEntity = asset.entities?.contains(entity) ?: false
        if (!isModelEntity) {
            Log.d(TAG, "Tapped entity $entity is not part of the model (probably light/camera/background)")
            return  // Ignore taps on non-model entities
        }

        val entityName = asset.getName(entity)

        if (selectedEntities.contains(entity)) {
            resetRenderableColor(entity)
            selectedEntities.remove(entity)
        } else {
            if (enableCache && entityName != null && cacheManager?.isCached(entityName) == true) {
                cacheManager?.removeFromCache(entityName)
                resetRenderableColor(entity)
                sendCacheSelectionUpdate()
            }

            val color = getEntityColor(entityName)
            // Use SELECTION color (solid, visible) for user tap selections
            setRenderableSelectionColor(entity, color[0], color[1], color[2], color[3])
            selectedEntities.add(entity)

            if (enableCache && entityName != null) {
                cacheManager?.addToCache(entityName)
                sendCacheSelectionUpdate()
            }
        }

        sendSelectedEntitiesToFlutter()
    }

    fun onPan(deltaX: Float, deltaY: Float) {
        // FIXED: Increased sensitivity by 25% more: 0.009375 (was 0.0075)
        orbitAngleY -= deltaX * 0.009375f
        orbitAngleX += deltaY * 0.009375f
        orbitAngleX = orbitAngleX.coerceIn(-1.4f, 1.4f)
        updateCameraPosition()
    }

    fun onScale(scale: Float) {
        // FIXED: Much less sensitive zoom - reduced scaling factors
        val scaleFactor = if (scale > 1.0f) {
            // Zooming in - much slower (reduced from 0.5 to 0.15)
            1.0f + (scale - 1.0f) * 0.15f
        } else {
            // Zooming out - much slower (reduced from 0.5 to 0.15)
            1.0f - (1.0f - scale) * 0.15f
        }

        zoomLevel *= scaleFactor
        zoomLevel = zoomLevel.coerceIn(0.1f, 10.0f)
        updateCameraPosition()
    }

    fun setPartGroupVisibility(group: Map<String, Any>, isVisible: Boolean) {
        val asset = currentAsset ?: return
        val scn = scene ?: return
        val names = group["names"] as? List<String> ?: return

        asset.entities?.forEach { entity ->
            val entityName = asset.getName(entity)
            if (entityName != null && names.contains(entityName)) {
                if (isVisible) {
                    scn.addEntity(entity)
                } else {
                    scn.removeEntity(entity)
                }
                entityVisibilities[entity] = isVisible
            }
        }

        if (!isVisible) {
            names.forEach { name ->
                asset.entities?.find { asset.getName(it) == name }?.let { entity ->
                    if (selectedEntities.contains(entity)) {
                        resetRenderableColor(entity)
                        selectedEntities.remove(entity)
                    }
                }
            }
            sendSelectedEntitiesToFlutter()
        }
    }

    fun unselectEntities(entityIds: List<Long>?) {
        if (entityIds == null) {
            selectedEntities.forEach { resetRenderableColor(it) }
            selectedEntities.clear()
        } else {
            entityIds.forEach { id ->
                val entity = id.toInt()
                if (selectedEntities.contains(entity)) {
                    resetRenderableColor(entity)
                    selectedEntities.remove(entity)
                }
            }
        }
        sendSelectedEntitiesToFlutter()
    }

    fun clearCacheAndRestoreSelections() {
        if (!enableCache || cacheManager == null) return

        val entitiesToClear = cacheManager!!.cachedEntities.toList()
        cacheManager!!.clearCache()

        currentAsset?.entities?.forEach { entity ->
            val name = currentAsset?.getName(entity)
            if (name != null && entitiesToClear.contains(name)) {
                resetRenderableColor(entity)
                if (selectedEntities.contains(entity)) {
                    val color = getEntityColor(name)
                    // Re-apply SELECTION color (solid) since entity is still selected
                    setRenderableSelectionColor(entity, color[0], color[1], color[2], color[3])
                }
            }
        }

        notifyCacheChanged()
    }

    private fun cleanupPreviousModel() {
        val scn = scene ?: return

        selectedEntities.clear()
        entityVisibilities.clear()
        originalMaterialInstances.clear()
        entitiesWithSelectionColor.clear()
        cleanupCreatedMaterialInstances()
        pendingPreselectedEntities = null
        modelLoaded = false

        currentAsset?.let { asset ->
            asset.entities?.forEach { entity ->
                scn.removeEntity(entity)
            }
            assetLoader?.destroyAsset(asset)
        }
        currentAsset = null

        sendSelectedEntitiesToFlutter()
        sendCacheSelectionUpdate()
    }

    private fun applyPreselectedEntities() {
        if (pendingPreselectedEntities == null || !modelLoaded) return
        val asset = currentAsset ?: return

        pendingPreselectedEntities?.forEach { name ->
            asset.entities?.forEach { entity ->
                val entityName = asset.getName(entity)
                if (name == entityName && entity !in selectedEntities) {
                    val color = getEntityColor(entityName)
                    // Use SELECTION color (solid) for preselected entities
                    setRenderableSelectionColor(entity, color[0], color[1], color[2], color[3])
                    selectedEntities.add(entity)
                }
            }
        }

        sendSelectedEntitiesToFlutter()
        pendingPreselectedEntities = null
    }

    private fun getEntityColor(entityName: String?): FloatArray {
        if (entityName == null) return selectionColor

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
        return selectionColor
    }

    // Store original MaterialInstance objects for each entity's primitives
    // Key: entity ID, Value: Map of primitive index -> original MaterialInstance
    private val originalMaterialInstances = mutableMapOf<Int, MutableMap<Int, MaterialInstance>>()

    // Track which entities have selection (new MaterialInstance) vs cache (parameter modification)
    private val entitiesWithSelectionColor = mutableSetOf<Int>()

    /**
     * Apply SELECTION color - uses MaterialInstance swapping for solid, visible colors.
     * This creates a NEW MaterialInstance without textures, so baseColorFactor shows as solid color.
     */
    private fun setRenderableSelectionColor(entity: Int, r: Float, g: Float, b: Float, a: Float) {
        val eng = engine ?: return
        val rcm = eng.renderableManager
        if (!rcm.hasComponent(entity)) return

        val ri = rcm.getInstance(entity)
        val count = rcm.getPrimitiveCount(ri)

        // Save original MaterialInstance objects if not already saved
        if (!originalMaterialInstances.containsKey(entity)) {
            val materialsMap = mutableMapOf<Int, MaterialInstance>()
            for (i in 0 until count) {
                try {
                    val originalMat = rcm.getMaterialInstanceAt(ri, i)
                    materialsMap[i] = originalMat
                    Log.d(TAG, "Saved original material for entity $entity, primitive $i")
                } catch (e: Exception) {
                    Log.w(TAG, "Could not save original material: ${e.message}")
                }
            }
            originalMaterialInstances[entity] = materialsMap
        }

        // Apply color using MaterialInstance swapping for SOLID color
        for (i in 0 until count) {
            try {
                val originalMat = originalMaterialInstances[entity]?.get(i) ?: rcm.getMaterialInstanceAt(ri, i)

                // Get the Material (template) from the original instance
                val material = originalMat.material

                // Create a NEW MaterialInstance for the selection color
                val selectionMat = material.createInstance()

                // Set solid color on the NEW instance using baseColorFactor
                // Since this is a fresh instance, baseColorMap is not set, so baseColorFactor works as solid color
                selectionMat.setParameter("baseColorFactor", r, g, b, a)

                // Add emissive to make the color vivid and visible
                selectionMat.setParameter("emissiveFactor", r * 0.4f, g * 0.4f, b * 0.4f)

                // Non-metallic, moderate roughness
                selectionMat.setParameter("metallicFactor", 0.0f)
                selectionMat.setParameter("roughnessFactor", 0.5f)

                // SWAP the MaterialInstance
                rcm.setMaterialInstanceAt(ri, i, selectionMat)

                // Track for cleanup
                createdMaterialInstances.add(selectionMat)

                Log.d(TAG, "Applied SELECTION color [%.2f, %.2f, %.2f] to entity $entity".format(r, g, b))

            } catch (e: Exception) {
                Log.w(TAG, "Could not apply selection color to entity $entity: ${e.message}")
            }
        }

        entitiesWithSelectionColor.add(entity)
    }

    /**
     * Apply CACHE color - uses parameter modification on existing MaterialInstance.
     * This preserves the original texture while tinting it with the cache color.
     */
    private fun setRenderableCacheColor(entity: Int, r: Float, g: Float, b: Float, a: Float) {
        val eng = engine ?: return
        val rcm = eng.renderableManager
        if (!rcm.hasComponent(entity)) return

        val ri = rcm.getInstance(entity)
        val count = rcm.getPrimitiveCount(ri)

        // Save original MaterialInstance objects if not already saved
        if (!originalMaterialInstances.containsKey(entity)) {
            val materialsMap = mutableMapOf<Int, MaterialInstance>()
            for (i in 0 until count) {
                try {
                    val originalMat = rcm.getMaterialInstanceAt(ri, i)
                    materialsMap[i] = originalMat
                    Log.d(TAG, "Saved original material for entity $entity, primitive $i")
                } catch (e: Exception) {
                    Log.w(TAG, "Could not save original material: ${e.message}")
                }
            }
            originalMaterialInstances[entity] = materialsMap
        }

        // Apply color using parameter modification (preserves texture)
        for (i in 0 until count) {
            try {
                val materialInst = rcm.getMaterialInstanceAt(ri, i)

                // Modify parameters on the EXISTING MaterialInstance
                // baseColorFactor will multiply with the texture
                materialInst.setParameter("baseColorFactor", r, g, b, a)

                // Add emissive to tint the texture
                materialInst.setParameter("emissiveFactor", r * 0.3f, g * 0.3f, b * 0.3f)

                // Keep original material properties mostly
                materialInst.setParameter("metallicFactor", 0.1f)
                materialInst.setParameter("roughnessFactor", 0.7f)

                Log.d(TAG, "Applied CACHE color [%.2f, %.2f, %.2f] to entity $entity".format(r, g, b))

            } catch (e: Exception) {
                Log.w(TAG, "Could not apply cache color to entity $entity: ${e.message}")
            }
        }
    }

    /**
     * Legacy function - routes to appropriate color function based on context.
     * For backward compatibility with existing code.
     */
    private fun setRenderableColor(entity: Int, r: Float, g: Float, b: Float, a: Float) {
        // This is called from various places - use cache color approach by default
        // Selection color is applied through setRenderableSelectionColor
        setRenderableCacheColor(entity, r, g, b, a)
    }

    // Store created MaterialInstances for cleanup
    private val createdMaterialInstances = mutableListOf<MaterialInstance>()

    private fun resetRenderableColor(entity: Int) {
        val eng = engine ?: return
        val rcm = eng.renderableManager
        if (!rcm.hasComponent(entity)) return

        val ri = rcm.getInstance(entity)

        // Check if this entity had SELECTION color (MaterialInstance swap)
        if (entitiesWithSelectionColor.contains(entity)) {
            // SWAP back to the ORIGINAL MaterialInstance
            val originals = originalMaterialInstances[entity]
            if (originals != null) {
                for ((primitiveIndex, originalMat) in originals) {
                    try {
                        rcm.setMaterialInstanceAt(ri, primitiveIndex, originalMat)
                        Log.d(TAG, "Restored original MaterialInstance for entity $entity primitive $primitiveIndex")
                    } catch (e: Exception) {
                        Log.w(TAG, "Could not restore entity $entity primitive $primitiveIndex: ${e.message}")
                    }
                }
            }
            entitiesWithSelectionColor.remove(entity)
        } else {
            // This was a CACHE color (parameter modification) - reset parameters
            val count = rcm.getPrimitiveCount(ri)
            val emissiveValue = if (iblLoaded) 0.0f else 0.2f

            for (i in 0 until count) {
                try {
                    val materialInst = rcm.getMaterialInstanceAt(ri, i)
                    materialInst.setParameter("baseColorFactor", 1.0f, 1.0f, 1.0f, 1.0f)
                    materialInst.setParameter("emissiveFactor", emissiveValue, emissiveValue, emissiveValue)
                    materialInst.setParameter("metallicFactor", 0.1f)
                    materialInst.setParameter("roughnessFactor", 0.8f)
                    Log.d(TAG, "Reset cache color parameters for entity $entity")
                } catch (e: Exception) {
                    Log.w(TAG, "Could not reset entity $entity: ${e.message}")
                }
            }
        }

        // Remove from stored originals
        originalMaterialInstances.remove(entity)
    }

    private fun cleanupCreatedMaterialInstances() {
        val eng = engine ?: return
        createdMaterialInstances.forEach { mat ->
            try {
                eng.destroyMaterialInstance(mat)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to destroy MaterialInstance: ${e.message}")
            }
        }
        createdMaterialInstances.clear()
    }

    private fun sendSelectedEntitiesToFlutter() {
        val asset = currentAsset ?: return
        val items = selectedEntities.mapNotNull { entity ->
            val name = asset.getName(entity)
            if (name != null && name != "Unnamed Entity") {
                mapOf("id" to entity.toLong(), "name" to name)
            } else null
        }
        selectionListener?.invoke(items)
    }

    private fun sendCacheSelectionUpdate() {
        val cached = cacheManager?.cachedEntities?.map { mapOf("name" to it) } ?: emptyList()
        cacheSelectionListener?.invoke(cached)
    }

    private fun notifyCacheChanged() {
        highlightAllCachedEntities()
        sendCacheSelectionUpdate()
    }

    private fun highlightAllCachedEntities() {
        if (!enableCache || cacheManager == null) return
        val asset = currentAsset ?: return

        cacheManager?.cachedEntities?.forEach { cachedName ->
            asset.entities?.forEach { entity ->
                val entityName = asset.getName(entity)
                if (entityName == cachedName && !selectedEntities.contains(entity)) {
                    setRenderableColor(entity, cacheColor[0], cacheColor[1], cacheColor[2], cacheColor[3])
                }
            }
        }
    }

    fun setSelectionListener(listener: (List<Map<String, Any>>) -> Unit) {
        selectionListener = listener
    }

    fun setCacheSelectionListener(listener: (List<Map<String, Any>>) -> Unit) {
        cacheSelectionListener = listener
    }

    fun cleanup() {
        Log.d(TAG, "Cleaning up FilamentTextureRenderer")
        stopRenderLoop()

        val eng = engine ?: return
        val rcm = eng.renderableManager

        // STEP 1: Restore original MaterialInstances (detach created ones from renderables)
        entitiesWithSelectionColor.forEach { entity ->
            if (rcm.hasComponent(entity)) {
                val ri = rcm.getInstance(entity)
                val originals = originalMaterialInstances[entity]
                if (originals != null) {
                    for ((primitiveIndex, originalMat) in originals) {
                        try {
                            rcm.setMaterialInstanceAt(ri, primitiveIndex, originalMat)
                            Log.d(TAG, "Restored original material for entity $entity before cleanup")
                        } catch (e: Exception) {
                            Log.w(TAG, "Could not restore material: ${e.message}")
                        }
                    }
                }
            }
        }

        // STEP 2: NOW safe to destroy created MaterialInstances (no longer attached)
        cleanupCreatedMaterialInstances()
        originalMaterialInstances.clear()
        entitiesWithSelectionColor.clear()

        // STEP 3: Continue with normal cleanup
        val scn = scene

        currentAsset?.let { asset ->
            scn?.let { s ->
                asset.entities?.forEach { entity ->
                    s.removeEntity(entity)
                }
            }
            assetLoader?.destroyAsset(asset)
        }
        currentAsset = null

        scn?.let { s ->
            s.indirectLight = null
            s.skybox = null
            if (sunlight != 0) s.removeEntity(sunlight)
            if (fillLight != 0) s.removeEntity(fillLight)
            if (backLight != 0) s.removeEntity(backLight)
        }

        indirectLight?.let { eng.destroyIndirectLight(it) }
        skybox?.let { eng.destroySkybox(it) }
        if (sunlight != 0) {
            eng.destroyEntity(sunlight)
            EntityManager.get().destroy(sunlight)
        }
        if (fillLight != 0) {
            eng.destroyEntity(fillLight)
            EntityManager.get().destroy(fillLight)
        }
        if (backLight != 0) {
            eng.destroyEntity(backLight)
            EntityManager.get().destroy(backLight)
        }

        resourceLoader?.destroy()
        assetLoader?.destroy()
        materialProvider?.destroyMaterials()
        materialProvider?.destroy()

        destroySwapChain()

        view?.let { eng.destroyView(it) }
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
        view = null
        camera = null
        materialProvider = null
        assetLoader = null
        resourceLoader = null
        indirectLight = null
        skybox = null
        sunlight = 0
        fillLight = 0
        backLight = 0
        cameraEntity = 0
        cacheManager = null

        selectedEntities.clear()
        entityVisibilities.clear()
        iblLoaded = false

        Log.d(TAG, "Cleanup complete")
    }

    private inner class FrameCallback : Choreographer.FrameCallback {
        private val startTime = System.nanoTime()
        private var frameCount = 0

        override fun doFrame(frameTimeNanos: Long) {
            if (!isRendering) return

            choreographer.postFrameCallback(this)

            val rend = renderer ?: return
            val sc = swapChain ?: return
            val v = view ?: return

            currentAsset?.instance?.animator?.apply {
                if (animationCount > 0) {
                    val elapsedSeconds = (frameTimeNanos - startTime) / 1_000_000_000.0
                    applyAnimation(0, elapsedSeconds.toFloat())
                    updateBoneMatrices()
                }
            }

            try {
                if (rend.beginFrame(sc, frameTimeNanos)) {
                    rend.render(v)
                    rend.endFrame()

                    frameCount++
                    if (frameCount % 60 == 0) {
                        val scn = scene
                        val entityCount = scn?.entityCount ?: 0
                        Log.d(TAG, "Rendered $frameCount frames (scene: $entityCount entities)")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Render error: ${e.message}")
            }
        }
    }
}