package com.example.interactive_3d.renderer

import android.util.Log
import com.google.android.filament.Engine
import com.google.android.filament.MaterialInstance
import com.google.android.filament.gltfio.FilamentAsset
import com.example.interactive_3d.Interactive3dCacheManager

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
     * Restores original materials on [entity], removing any selection or
     * cache highlight.
     */
    fun resetColor(entity: Int, engine: Engine) {
        val rcm = engine.renderableManager
        if (!rcm.hasComponent(entity)) return
        val ri = rcm.getInstance(entity)

        if (entitiesWithSelectionColor.contains(entity) || entitiesWithCacheColor.contains(entity)) {
            // Entity had a new MaterialInstance (selection or cache) — restore originals
            val originals = originalMaterials[entity]
            if (originals != null) {
                for ((idx, mat) in originals) {
                    try { rcm.setMaterialInstanceAt(ri, idx, mat) }
                    catch (e: Exception) { Log.w(TAG, "Could not restore material: ${e.message}") }
                }
            }
            entitiesWithSelectionColor.remove(entity)
            entitiesWithCacheColor.remove(entity)
        } else {
            // No backup exists — reset to default PBR values
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

        originalMaterials.remove(entity)
    }

    /**
     * Highlights all entities that are in the persistent cache.
     */
    fun highlightCachedEntities(asset: FilamentAsset, engine: Engine) {
        if (!enableCache || cacheManager == null) return
        cacheManager?.cachedEntities?.forEach { cachedName ->
            asset.entities?.forEach { entity ->
                if (asset.getName(entity) == cachedName && entity !in selectedEntities) {
                    applyCacheColor(entity, engine)
                }
            }
        }
    }

    /**
     * Full refresh: reset everything, then re-apply cache and selection colors.
     * Matches iOS refreshCacheHighlights behavior exactly.
     */
    fun refreshAllHighlights(asset: FilamentAsset, engine: Engine, clearSelections: Boolean) {
        // 1. Reset ALL entities to original materials
        asset.entities?.forEach { entity ->
            if (originalMaterials.containsKey(entity) ||
                entitiesWithSelectionColor.contains(entity) ||
                entitiesWithCacheColor.contains(entity)) {
                resetColor(entity, engine)
            }
        }

        // 2. Apply cache color (takes priority in appearance)
        val cachedSet = mutableSetOf<String>()
        if (enableCache && cacheManager != null) {
            cacheManager?.cachedEntities?.forEach { cachedName ->
                cachedSet.add(cachedName)
                asset.entities?.forEach { entity ->
                    if (asset.getName(entity) == cachedName) {
                        applyCacheColor(entity, engine)
                    }
                }
            }
        }

        // 3. Re-apply selection color ONLY to entities NOT in cache
        for (entity in selectedEntities.toSet()) {
            val name = asset.getName(entity)
            if (name != null && !cachedSet.contains(name)) {
                val color = resolveColor(name)
                applySelectionColor(entity, color, engine)
            }
        }

        // 4. Clear selections if configured
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
     * Resets all selection state. Call before loading a new model.
     */
    fun reset(engine: Engine) {
        selectedEntities.clear()
        entityVisibilities.clear()
        destroyCreatedInstances(engine)
        originalMaterials.clear()
        entitiesWithSelectionColor.clear()
        entitiesWithCacheColor.clear()
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