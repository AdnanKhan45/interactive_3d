package com.example.interactive_3d.renderer

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.filament.Engine
import com.google.android.filament.Scene
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.ResourceLoader
import java.nio.ByteBuffer

/**
 * Loads glTF/GLB models into the Filament scene.
 *
 * Handles resource resolution for multi-file glTF assets, adds entities
 * to the scene, and applies an initial material pass to ensure the model
 * is visible even before IBL lighting arrives.
 */
internal class ModelLoader(
    private val mainHandler: Handler = Handler(Looper.getMainLooper())
) {

    private companion object {
        const val TAG = "ModelLoader"
    }

    var currentAsset: FilamentAsset? = null
        private set
    var modelLoaded = false
        private set

    /**
     * Loads a model from [buffer] into the [scene].
     *
     * [resources] maps URI names to byte arrays for multi-file glTF assets
     * (textures, .bin files). After loading, an initial material pass adjusts
     * metallic and roughness factors so the model looks reasonable under the
     * default lighting (before IBL loads).
     */
    fun loadModel(
        engine: Engine,
        scene: Scene,
        assetLoader: AssetLoader,
        resourceLoader: ResourceLoader,
        buffer: ByteBuffer,
        fileName: String,
        resources: Map<String, ByteArray>
    ): FilamentAsset? {
        buffer.rewind()
        val asset = assetLoader.createAsset(buffer)
        if (asset == null) {
            Log.e(TAG, "Failed to create asset from $fileName")
            return null
        }

        currentAsset = asset

        // Resolve external resources (textures, .bin)
        if (resources.isNotEmpty()) {
            asset.resourceUris?.forEach { uri ->
                resources[uri]?.let { data ->
                    resourceLoader.addResourceData(uri, ByteBuffer.wrap(data))
                }
            }
        }
        resourceLoader.loadResources(asset)
        asset.releaseSourceData()

        // Add all entities to the scene
        asset.entities?.forEach { entity -> scene.addEntity(entity) }

        // Apply initial PBR defaults so the model is visible under default lights
        applyInitialMaterials(engine, asset)

        modelLoaded = true
        return asset
    }

    /**
     * Removes the current model from [scene] and destroys the asset.
     */
    fun cleanupCurrentModel(scene: Scene, assetLoader: AssetLoader) {
        currentAsset?.let { asset ->
            asset.entities?.forEach { scene.removeEntity(it) }
            assetLoader.destroyAsset(asset)
        }
        currentAsset = null
        modelLoaded = false
    }

    /**
     * Returns the bounding box center and half-extent for camera framing.
     */
    fun getBoundingBox(): Pair<FloatArray, FloatArray>? {
        val asset = currentAsset ?: return null
        val bb = asset.boundingBox
        return Pair(bb.center, bb.halfExtent)
    }

    /**
     * Adjusts materials so the model is visible under the default three-point
     * lighting, before IBL provides full PBR reflections. Processes entities
     * in chunks of 5 to avoid blocking the main thread.
     */
    private fun applyInitialMaterials(engine: Engine, asset: FilamentAsset) {
        val rcm = engine.renderableManager
        val entities = asset.entities?.toList() ?: return

        fun processChunk(startIndex: Int) {
            val endIndex = minOf(startIndex + 5, entities.size)
            for (i in startIndex until endIndex) {
                val entity = entities[i]
                if (!rcm.hasComponent(entity)) continue
                val ri = rcm.getInstance(entity)
                val count = rcm.getPrimitiveCount(ri)

                for (j in 0 until count) {
                    try {
                        val mat = rcm.getMaterialInstanceAt(ri, j)
                        mat.setParameter("metallicFactor", 0.1f)
                        mat.setParameter("roughnessFactor", 0.8f)
                    } catch (e: Exception) {
                        Log.w(TAG, "Could not modify material: ${e.message}")
                    }
                }
            }
            if (endIndex < entities.size) {
                mainHandler.post { processChunk(endIndex) }
            }
        }
        processChunk(0)
    }

    /**
     * After IBL loads, resets emissive factors that were used for default
     * lighting visibility.
     */
    fun restoreEmissiveAfterIBL(engine: Engine) {
        val asset = currentAsset ?: return
        val rcm = engine.renderableManager

        asset.entities?.forEach { entity ->
            if (!rcm.hasComponent(entity)) return@forEach
            val ri = rcm.getInstance(entity)
            val count = rcm.getPrimitiveCount(ri)
            for (i in 0 until count) {
                try {
                    rcm.getMaterialInstanceAt(ri, i)
                        .setParameter("emissiveFactor", 0.0f, 0.0f, 0.0f)
                } catch (_: Exception) {}
            }
        }
    }
}