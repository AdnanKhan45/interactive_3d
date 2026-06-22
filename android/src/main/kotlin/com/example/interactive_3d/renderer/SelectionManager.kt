package com.example.interactive_3d.renderer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.android.filament.Engine
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Texture
import com.google.android.filament.TextureSampler
import com.google.android.filament.android.TextureHelper
import com.google.android.filament.gltfio.FilamentAsset
import com.example.interactive_3d.Interactive3dCacheManager
import kotlin.math.floor
import kotlin.math.log2

/**
 * Handles entity selection, highlighting, and cache coloring.
 *
 * Selection works by replacing Filament material instances with solid-color
 * copies that override the Ubershader texture indices. Original materials
 * are stored in [originalMaterials] so they can be restored on deselection.
 *
 * All material updates execute synchronously on the calling thread (which
 * must be the main thread per Filament's requirement).
 */
internal class SelectionManager {

    private companion object {
        const val TAG = "SelectionManager"
        const val MAX_TEXTURE_DIM = 2048
    }

    // Currently selected entity IDs
    val selectedEntities = mutableSetOf<Int>()

    // Configurable colors
    var selectionColor = floatArrayOf(0f, 1f, 0f, 1f)
    var patchColors: List<Map<String, Any>>? = null

    // Set by the renderer after IBL loads — controls emissive fallback in resetColor
    var iblLoaded = false

    // Original material backup for selected/cached entities
    private val originalMaterials = mutableMapOf<Int, MutableMap<Int, MaterialInstance>>()
    private val entitiesWithSelectionColor = mutableSetOf<Int>()
    private val entitiesWithCacheColor = mutableSetOf<Int>()
    private val createdInstances = mutableListOf<MaterialInstance>()

    // Cache
    var enableCache = false
    var cacheManager: Interactive3dCacheManager? = null
    var cacheColor = floatArrayOf(0.8f, 0.8f, 0.2f, 0.6f)
    var clearSelectionsOnHighlight = false

    // PBR override state, independent of selection and cache.
    // overrideParams accumulates merged params per entity across calls.
    // overrideMaterials holds the live MaterialInstances applied to the renderable.
    // entitiesWithOverrideApplied tracks which entities currently render the override.
    private val overrideParams = mutableMapOf<Int, MutableMap<String, Any>>()
    private val overrideMaterials = mutableMapOf<Int, MutableMap<Int, MaterialInstance>>()
    private val entitiesWithOverrideApplied = mutableSetOf<Int>()

    // Per-entity uploaded base color textures. GPU resources with manual lifecycle,
    // destroyed wherever overrideMaterials is.
    private val overrideTextures = mutableMapOf<Int, Texture>()

    // Part visibility tracking
    val entityVisibilities = mutableMapOf<Int, Boolean>()

    // Event listeners
    var onSelectionChanged: ((List<Map<String, Any>>) -> Unit)? = null
    var onCacheSelectionChanged: ((List<Map<String, Any>>) -> Unit)? = null

    /**
     * Processes a tap on [entity]. Toggles selection state and applies or
     * removes the highlight color.
     */
    fun handleTap(entity: Int, asset: FilamentAsset, engine: Engine) {
        val entityName = asset.getName(entity)

        if (selectedEntities.contains(entity)) {
            resetColor(entity, engine)
            selectedEntities.remove(entity)
        } else {
            // If tapping a cached entity, uncache it first
            if (enableCache && entityName != null && cacheManager?.isCached(entityName) == true) {
                cacheManager?.removeFromCache(entityName)
                resetColor(entity, engine)
                notifyCacheChanged()
            }

            val color = resolveColor(entityName)
            applySelectionColor(entity, color, engine)
            selectedEntities.add(entity)

            if (enableCache && entityName != null) {
                cacheManager?.addToCache(entityName)
                notifyCacheChanged()
            }
        }

        notifySelectionChanged(asset)
    }

    /**
     * Applies a solid selection color to all primitives of [entity].
     *
     * Backs up original materials on first call, then replaces them with
     * solid-color instances that disable texture sampling so baseColorFactor
     * is the sole color source.
     */
    fun applySelectionColor(entity: Int, color: FloatArray, engine: Engine) {
        val rcm = engine.renderableManager
        if (!rcm.hasComponent(entity)) return

        val ri = rcm.getInstance(entity)
        val count = rcm.getPrimitiveCount(ri)

        // Backup originals on first highlight
        if (!originalMaterials.containsKey(entity)) {
            val backup = mutableMapOf<Int, MaterialInstance>()
            for (i in 0 until count) {
                try { backup[i] = rcm.getMaterialInstanceAt(ri, i) }
                catch (e: Exception) { Log.w(TAG, "Could not backup material: ${e.message}") }
            }
            originalMaterials[entity] = backup
        }

        // Create solid-color instances
        for (i in 0 until count) {
            try {
                val originalMat = originalMaterials[entity]?.get(i)
                    ?: rcm.getMaterialInstanceAt(ri, i)
                val selectionMat = originalMat.material.createInstance()

                // Disable texture sampling so baseColorFactor is the sole color source
                selectionMat.setParameter("baseColorIndex", -1)
                selectionMat.setParameter("metallicRoughnessIndex", -1)
                selectionMat.setParameter("normalIndex", -1)
                selectionMat.setParameter("emissiveIndex", -1)

                selectionMat.setParameter("baseColorFactor", color[0], color[1], color[2], color[3])
                selectionMat.setParameter("emissiveFactor", 0.0f, 0.0f, 0.0f)
                selectionMat.setParameter("metallicFactor", 0.0f)
                selectionMat.setParameter("roughnessFactor", 1.0f)

                rcm.setMaterialInstanceAt(ri, i, selectionMat)
                createdInstances.add(selectionMat)
            } catch (e: Exception) {
                Log.w(TAG, "Could not apply selection color: ${e.message}")
            }
        }
        entitiesWithSelectionColor.add(entity)
        // Selection takes over visually; override is no longer rendered.
        entitiesWithOverrideApplied.remove(entity)
    }

    /**
     * Applies cache highlight color by creating new MaterialInstances
     * (same approach as selection color). Backs up originals so they can
     * be restored by [resetColor].
     */
    fun applyCacheColor(entity: Int, engine: Engine) {
        val rcm = engine.renderableManager
        if (!rcm.hasComponent(entity)) return

        val ri = rcm.getInstance(entity)
        val count = rcm.getPrimitiveCount(ri)

        // Backup originals on first highlight
        if (!originalMaterials.containsKey(entity)) {
            val backup = mutableMapOf<Int, MaterialInstance>()
            for (i in 0 until count) {
                try { backup[i] = rcm.getMaterialInstanceAt(ri, i) }
                catch (e: Exception) { Log.w(TAG, "Could not backup material: ${e.message}") }
            }
            originalMaterials[entity] = backup
        }

        // Create new cache-colored instances
        for (i in 0 until count) {
            try {
                val originalMat = originalMaterials[entity]?.get(i)
                    ?: rcm.getMaterialInstanceAt(ri, i)
                val cacheMat = originalMat.material.createInstance()

                // Disable texture sampling so cacheColor is the sole color source
                cacheMat.setParameter("baseColorIndex", -1)
                cacheMat.setParameter("metallicRoughnessIndex", -1)
                cacheMat.setParameter("normalIndex", -1)
                cacheMat.setParameter("emissiveIndex", -1)

                cacheMat.setParameter("baseColorFactor", cacheColor[0], cacheColor[1], cacheColor[2], cacheColor[3])
                cacheMat.setParameter("emissiveFactor", 0.0f, 0.0f, 0.0f)
                cacheMat.setParameter("metallicFactor", 0.1f)
                cacheMat.setParameter("roughnessFactor", 0.7f)

                rcm.setMaterialInstanceAt(ri, i, cacheMat)
                createdInstances.add(cacheMat)
            } catch (e: Exception) {
                Log.w(TAG, "Could not apply cache color: ${e.message}")
            }
        }
        entitiesWithCacheColor.add(entity)
    }

    /**
     * Merges [params] into the entity's override and applies the override
     * material if the entity is not currently selected. Override visually
     * wins over cache; cache remains in storage.
     */
    fun applyMaterialOverride(entity: Int, params: Map<String, Any>, engine: Engine) {
        val rcm = engine.renderableManager
        if (!rcm.hasComponent(entity)) return
        val ri = rcm.getInstance(entity)
        val count = rcm.getPrimitiveCount(ri)

        // Snapshot GLB original on first modification of this entity.
        if (!originalMaterials.containsKey(entity)) {
            val backup = mutableMapOf<Int, MaterialInstance>()
            for (i in 0 until count) {
                try { backup[i] = rcm.getMaterialInstanceAt(ri, i) }
                catch (e: Exception) { Log.w(TAG, "Could not backup material: ${e.message}") }
            }
            originalMaterials[entity] = backup
        }

        // Merge new params into the accumulated override state.
        val merged = overrideParams.getOrPut(entity) { mutableMapOf() }
        for ((k, v) in params) merged[k] = v

        // Build override MaterialInstances on first use, reuse afterwards.
        val mats = overrideMaterials.getOrPut(entity) {
            val newMap = mutableMapOf<Int, MaterialInstance>()
            for (i in 0 until count) {
                try {
                    val orig = originalMaterials[entity]?.get(i) ?: continue
                    newMap[i] = orig.material.createInstance()
                } catch (e: Exception) {
                    Log.w(TAG, "Could not create override instance: ${e.message}")
                }
            }
            newMap
        }

        // Apply every accumulated param, then bind the uploaded texture if present.
        for ((_, mat) in mats) {
            applyOverrideParamsToInstance(mat, merged)
            overrideTextures[entity]?.let { bindBaseColorTexture(mat, it) }
        }

        // Selection wins visually; only stash the deselect target.
        if (entity in entitiesWithSelectionColor) return

        for ((idx, mat) in mats) {
            try { rcm.setMaterialInstanceAt(ri, idx, mat) }
            catch (e: Exception) { Log.w(TAG, "Could not apply override: ${e.message}") }
        }
        entitiesWithOverrideApplied.add(entity)
        entitiesWithCacheColor.remove(entity)
    }

    /** Removes the override on [entity] and restores GLB original if visible. */
    fun resetMaterialOverride(entity: Int, engine: Engine) {
        // Destroy override instances first so they cannot be reused.
        overrideMaterials.remove(entity)?.values?.forEach { mat ->
            try { engine.destroyMaterialInstance(mat) }
            catch (e: Exception) { Log.w(TAG, "Failed to destroy override instance: ${e.message}") }
        }
        overrideTextures.remove(entity)?.let { tex ->
            try { engine.destroyTexture(tex) }
            catch (e: Exception) { Log.w(TAG, "Failed to destroy override texture: ${e.message}") }
        }
        overrideParams.remove(entity)

        if (entity !in entitiesWithOverrideApplied) return
        entitiesWithOverrideApplied.remove(entity)

        val rcm = engine.renderableManager
        if (!rcm.hasComponent(entity)) return
        val ri = rcm.getInstance(entity)

        originalMaterials[entity]?.forEach { (idx, mat) ->
            try { rcm.setMaterialInstanceAt(ri, idx, mat) }
            catch (e: Exception) { Log.w(TAG, "Could not restore on override reset: ${e.message}") }
        }

        if (entity !in entitiesWithSelectionColor && entity !in entitiesWithCacheColor) {
            originalMaterials.remove(entity)
        }
    }

    /** Removes every active override. */
    fun resetAllMaterialOverrides(engine: Engine) {
        for (entity in overrideParams.keys.toList()) {
            resetMaterialOverride(entity, engine)
        }
    }

    /**
     * Looks up entities by name and applies overrides. Used both on model load
     * (initialMaterialOverrides) and from the controller (setEntityMaterials).
     */
    fun applyOverridesByName(
        overrides: List<Map<String, Any>>,
        asset: FilamentAsset,
        engine: Engine,
    ) {
        if (overrides.isEmpty()) return
        for (entry in overrides) {
            val name = entry["name"] as? String ?: continue
            val params = entry.filterKeys { it != "name" }
            asset.entities?.forEach { entity ->
                if (asset.getName(entity) == name) {
                    applyMaterialOverride(entity, params, engine)
                }
            }
        }
    }

    /** Resets overrides for entities matched by [names], or all when null. */
    fun resetOverridesByName(
        names: List<String>?,
        asset: FilamentAsset,
        engine: Engine,
    ) {
        if (names == null) {
            resetAllMaterialOverrides(engine)
            return
        }
        for (name in names) {
            asset.entities?.forEach { entity ->
                if (asset.getName(entity) == name) {
                    resetMaterialOverride(entity, engine)
                }
            }
        }
    }

    /** Looks up entities by name and uploads a base color texture to each. */
    fun applyTexturesByName(
        textures: List<Map<String, Any>>,
        asset: FilamentAsset,
        engine: Engine,
    ) {
        if (textures.isEmpty()) return
        for (entry in textures) {
            val name = entry["name"] as? String ?: continue
            val bytes = entry["texture"] as? ByteArray ?: continue
            asset.entities?.forEach { entity ->
                if (asset.getName(entity) == name) {
                    applyEntityTexture(entity, bytes, engine)
                }
            }
        }
    }

    /** Resets textures for entities matched by [names], or all when null. */
    fun resetTexturesByName(
        names: List<String>?,
        asset: FilamentAsset,
        engine: Engine,
    ) {
        if (names == null) {
            for (entity in overrideTextures.keys.toList()) {
                resetEntityTexture(entity, engine)
            }
            return
        }
        for (name in names) {
            asset.entities?.forEach { entity ->
                if (asset.getName(entity) == name) {
                    resetEntityTexture(entity, engine)
                }
            }
        }
    }

    /**
     * Decodes [bytes] into an sRGB texture and binds it as [entity]'s base
     * color map, merged onto any existing override. Rebinds the reused
     * instances to the new texture before freeing the old one.
     */
    fun applyEntityTexture(entity: Int, bytes: ByteArray, engine: Engine) {
        if (!engine.renderableManager.hasComponent(entity)) return
        val texture = decodeSrgbTexture(bytes, engine)
        if (texture == null) {
            Log.w(TAG, "Could not decode texture for entity $entity")
            return
        }
        val old = overrideTextures.put(entity, texture)
        applyMaterialOverride(entity, emptyMap(), engine)
        if (old != null) {
            try { engine.destroyTexture(old) }
            catch (e: Exception) { Log.w(TAG, "Failed to destroy old texture: ${e.message}") }
        }
    }

    /**
     * Removes the uploaded texture on [entity], keeping any color/PBR override.
     * Rebuilds the override instances so the GLB base color reappears; falls
     * back to a full override reset when nothing else remains.
     */
    fun resetEntityTexture(entity: Int, engine: Engine) {
        if (!overrideTextures.containsKey(entity)) return
        if (overrideParams[entity].isNullOrEmpty()) {
            resetMaterialOverride(entity, engine)
            return
        }
        val tex = overrideTextures.remove(entity)
        overrideMaterials.remove(entity)?.values?.forEach { mat ->
            try { engine.destroyMaterialInstance(mat) }
            catch (e: Exception) { Log.w(TAG, "Failed to destroy override instance: ${e.message}") }
        }
        applyMaterialOverride(entity, emptyMap(), engine)
        tex?.let {
            try { engine.destroyTexture(it) }
            catch (e: Exception) { Log.w(TAG, "Failed to destroy texture: ${e.message}") }
        }
    }

    private fun decodeSrgbTexture(bytes: ByteArray, engine: Engine): Texture? {
        var bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val maxDim = maxOf(bitmap.width, bitmap.height)
        if (maxDim > MAX_TEXTURE_DIM) {
            val scale = MAX_TEXTURE_DIM.toFloat() / maxDim
            val w = (bitmap.width * scale).toInt().coerceAtLeast(1)
            val h = (bitmap.height * scale).toInt().coerceAtLeast(1)
            Log.w(TAG, "Texture ${bitmap.width}x${bitmap.height} exceeds ${MAX_TEXTURE_DIM}px, downsampling to ${w}x${h}")
            val scaled = Bitmap.createScaledBitmap(bitmap, w, h, true)
            if (scaled !== bitmap) bitmap.recycle()
            bitmap = scaled
        }
        val levels = (floor(log2(maxOf(bitmap.width, bitmap.height).toDouble())).toInt() + 1)
            .coerceAtLeast(1)
        val texture = Texture.Builder()
            .width(bitmap.width)
            .height(bitmap.height)
            .levels(levels)
            .format(Texture.InternalFormat.SRGB8_A8)
            .sampler(Texture.Sampler.SAMPLER_2D)
            // GEN_MIPMAPPABLE is required by generateMipmaps; DEFAULT omits it.
            .usage(Texture.Usage.DEFAULT or Texture.Usage.GEN_MIPMAPPABLE)
            .build(engine)
        try {
            TextureHelper.setBitmap(engine, texture, 0, bitmap)
            texture.generateMipmaps(engine)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to upload texture: ${e.message}")
            engine.destroyTexture(texture)
            bitmap.recycle()
            return null
        }
        bitmap.recycle()
        return texture
    }

    private fun bindBaseColorTexture(mat: MaterialInstance, texture: Texture) {
        val sampler = TextureSampler(
            TextureSampler.MinFilter.LINEAR_MIPMAP_LINEAR,
            TextureSampler.MagFilter.LINEAR,
            TextureSampler.WrapMode.REPEAT,
        )
        mat.setParameter("baseColorMap", texture, sampler)
        // Force sampling for entities whose GLB material had no base color map.
        mat.setParameter("baseColorIndex", 0)
    }

    private fun applyOverrideParamsToInstance(mat: MaterialInstance, params: Map<String, Any>) {
        (params["color"] as? List<Double>)?.takeIf { it.size == 4 }?.let { c ->
            // baseColorFactor multiplies baseColorMap, preserving GLB textures.
            mat.setParameter(
                "baseColorFactor",
                c[0].toFloat(), c[1].toFloat(), c[2].toFloat(), c[3].toFloat()
            )
        }
        (params["metallic"] as? Double)?.let { mat.setParameter("metallicFactor", it.toFloat()) }
        (params["roughness"] as? Double)?.let { mat.setParameter("roughnessFactor", it.toFloat()) }
        (params["emissive"] as? List<Double>)?.takeIf { it.size == 3 }?.let { e ->
            mat.setParameter(
                "emissiveFactor",
                e[0].toFloat(), e[1].toFloat(), e[2].toFloat()
            )
        }
    }

    /**
     * Restores original materials on [entity], removing any selection or
     * cache highlight.
     */
    fun resetColor(entity: Int, engine: Engine) {
        val rcm = engine.renderableManager
        if (!rcm.hasComponent(entity)) return
        val ri = rcm.getInstance(entity)

        if (entitiesWithSelectionColor.contains(entity) || entitiesWithCacheColor.contains(entity)) {
            // Restore to override material if one exists, otherwise GLB original.
            val restoreTo = overrideMaterials[entity] ?: originalMaterials[entity]
            if (restoreTo != null) {
                for ((idx, mat) in restoreTo) {
                    try { rcm.setMaterialInstanceAt(ri, idx, mat) }
                    catch (e: Exception) { Log.w(TAG, "Could not restore material: ${e.message}") }
                }
            }
            entitiesWithSelectionColor.remove(entity)
            entitiesWithCacheColor.remove(entity)

            if (overrideMaterials.containsKey(entity)) {
                entitiesWithOverrideApplied.add(entity)
            }
        } else {
            // No backup exists — reset to default PBR values.
            val count = rcm.getPrimitiveCount(ri)
            val emissiveValue = if (iblLoaded) 0.0f else 0.2f
            for (i in 0 until count) {
                try {
                    val mat = rcm.getMaterialInstanceAt(ri, i)
                    mat.setParameter("baseColorFactor", 1.0f, 1.0f, 1.0f, 1.0f)
                    mat.setParameter("emissiveFactor", emissiveValue, emissiveValue, emissiveValue)
                    mat.setParameter("metallicFactor", 0.1f)
                    mat.setParameter("roughnessFactor", 0.8f)
                } catch (e: Exception) {
                    Log.w(TAG, "Could not reset material: ${e.message}")
                }
            }
        }

        // Preserve the GLB-original snapshot if an override is still registered.
        if (entity !in entitiesWithOverrideApplied) {
            originalMaterials.remove(entity)
        }
    }

    /**
     * Highlights all cached entities. Skips overridden entities so the
     * override remains visible.
     */
    fun highlightCachedEntities(asset: FilamentAsset, engine: Engine) {
        if (!enableCache || cacheManager == null) return
        cacheManager?.cachedEntities?.forEach { cachedName ->
            asset.entities?.forEach { entity ->
                if (asset.getName(entity) == cachedName &&
                    entity !in selectedEntities &&
                    entity !in entitiesWithOverrideApplied
                ) {
                    applyCacheColor(entity, engine)
                }
            }
        }
    }

    /**
     * Resets everything and re-applies in priority order:
     * selection > override > cache > GLB original.
     */
    fun refreshAllHighlights(asset: FilamentAsset, engine: Engine, clearSelections: Boolean) {
        // 1. Reset entities that had selection or cache visuals. resetColor
        //    internally restores to override material when one is registered.
        asset.entities?.forEach { entity ->
            if (entitiesWithSelectionColor.contains(entity) ||
                entitiesWithCacheColor.contains(entity)) {
                resetColor(entity, engine)
            }
        }

        // 2. Apply cache color, skipping any entity with an override.
        val cachedSet = mutableSetOf<String>()
        if (enableCache && cacheManager != null) {
            cacheManager?.cachedEntities?.forEach { cachedName ->
                cachedSet.add(cachedName)
                asset.entities?.forEach { entity ->
                    if (asset.getName(entity) == cachedName &&
                        entity !in entitiesWithOverrideApplied &&
                        !overrideParams.containsKey(entity)
                    ) {
                        applyCacheColor(entity, engine)
                    }
                }
            }
        }

        // 3. Selection on top regardless of cache or override.
        for (entity in selectedEntities.toSet()) {
            val name = asset.getName(entity)
            if (name != null && !cachedSet.contains(name)) {
                val color = resolveColor(name)
                applySelectionColor(entity, color, engine)
            }
        }

        if (clearSelections) {
            selectedEntities.clear()
        }
    }

    /**
     * Clears the persistent cache and restores materials for previously
     * cached entities. Active selections are re-applied with selection color.
     */
    fun clearCacheAndRestore(asset: FilamentAsset, engine: Engine) {
        if (!enableCache || cacheManager == null) return

        val entitiesToClear = cacheManager!!.cachedEntities.toList()
        cacheManager!!.clearCache()

        asset.entities?.forEach { entity ->
            val name = asset.getName(entity)
            if (name != null && entitiesToClear.contains(name)) {
                resetColor(entity, engine)
                // If entity is still actively selected, re-apply its selection color
                if (selectedEntities.contains(entity)) {
                    val color = resolveColor(name)
                    applySelectionColor(entity, color, engine)
                }
            }
        }
        notifyCacheChanged()
    }

    /**
     * Applies preselected entities. Call after model loading completes.
     */
    fun applyPreselections(names: List<String>?, asset: FilamentAsset, engine: Engine) {
        if (names == null) return
        names.forEach { name ->
            asset.entities?.forEach { entity ->
                if (asset.getName(entity) == name && entity !in selectedEntities) {
                    val color = resolveColor(name)
                    applySelectionColor(entity, color, engine)
                    selectedEntities.add(entity)
                }
            }
        }
        notifySelectionChanged(asset)
    }

    /**
     * Unselects entities by ID, or all if [entityIds] is null.
     */
    fun unselectEntities(entityIds: List<Long>?, engine: Engine, asset: FilamentAsset?) {
        if (entityIds == null) {
            selectedEntities.forEach { resetColor(it, engine) }
            selectedEntities.clear()
        } else {
            entityIds.forEach { id ->
                val entity = id.toInt()
                if (selectedEntities.remove(entity)) {
                    resetColor(entity, engine)
                }
            }
        }
        asset?.let { notifySelectionChanged(it) }
    }

    /**
     * Resolves the highlight color for [entityName].
     * Checks [patchColors] first, then falls back to the global [selectionColor].
     */
    fun resolveColor(entityName: String?): FloatArray {
        if (entityName == null) return selectionColor
        patchColors?.forEach { patch ->
            if (patch["name"] == entityName) {
                val c = patch["color"] as? List<Double>
                if (c?.size == 4) {
                    return floatArrayOf(c[0].toFloat(), c[1].toFloat(), c[2].toFloat(), c[3].toFloat())
                }
            }
        }
        return selectionColor
    }

    // -- Events --

    fun notifySelectionChanged(asset: FilamentAsset) {
        val items = selectedEntities.mapNotNull { entity ->
            val name = asset.getName(entity)
            if (name != null && name != "Unnamed Entity") {
                mapOf("id" to entity.toLong(), "name" to name)
            } else null
        }
        onSelectionChanged?.invoke(items)
    }

    fun notifyCacheChanged() {
        val cached = cacheManager?.cachedEntities?.map { mapOf("name" to it) } ?: emptyList()
        onCacheSelectionChanged?.invoke(cached)
    }

    // -- Cleanup --

    /**
     * Destroys all created material instances and clears tracking state.
     */
    fun destroyCreatedInstances(engine: Engine) {
        createdInstances.forEach { mat ->
            try { engine.destroyMaterialInstance(mat) }
            catch (e: Exception) { Log.w(TAG, "Failed to destroy MaterialInstance: ${e.message}") }
        }
        createdInstances.clear()
    }

    /**
     * Resets all selection and override state. Call before loading a new model.
     */
    fun reset(engine: Engine) {
        selectedEntities.clear()
        entityVisibilities.clear()
        destroyCreatedInstances(engine)
        destroyOverrideInstances(engine)
        destroyOverrideTextures(engine)
        originalMaterials.clear()
        entitiesWithSelectionColor.clear()
        entitiesWithCacheColor.clear()
        entitiesWithOverrideApplied.clear()
        overrideParams.clear()
    }

    private fun destroyOverrideInstances(engine: Engine) {
        overrideMaterials.values.forEach { primitives ->
            primitives.values.forEach { mat ->
                try { engine.destroyMaterialInstance(mat) }
                catch (e: Exception) { Log.w(TAG, "Failed to destroy override instance: ${e.message}") }
            }
        }
        overrideMaterials.clear()
    }

    private fun destroyOverrideTextures(engine: Engine) {
        overrideTextures.values.forEach { tex ->
            try { engine.destroyTexture(tex) }
            catch (e: Exception) { Log.w(TAG, "Failed to destroy override texture: ${e.message}") }
        }
        overrideTextures.clear()
    }

    /**
     * Full cleanup — restores originals then destroys everything.
     */
    fun cleanup(engine: Engine) {
        val allColoredEntities = entitiesWithSelectionColor + entitiesWithCacheColor
        allColoredEntities.forEach { entity ->
            val rcm = engine.renderableManager
            if (rcm.hasComponent(entity)) {
                val ri = rcm.getInstance(entity)
                originalMaterials[entity]?.forEach { (idx, mat) ->
                    try { rcm.setMaterialInstanceAt(ri, idx, mat) }
                    catch (_: Exception) {}
                }
            }
        }
        reset(engine)
    }
}