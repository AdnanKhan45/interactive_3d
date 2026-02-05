package com.example.interactive_3d

import android.util.Log
import com.google.android.filament.gltfio.FilamentAsset
import java.nio.ByteBuffer

/**
 * Cache manager for loaded 3D models to avoid re-parsing on each load.
 * Stores models by their filename for quick retrieval.
 */
object ModelCacheManager {
    private const val TAG = "ModelCacheManager"
    private const val MAX_CACHE_SIZE = 5 // Maximum number of models to cache

    // Cache storage: filename -> CachedModel
    private val cache = mutableMapOf<String, CachedModel>()

    // LRU tracking: filename -> last access time
    private val accessOrder = mutableMapOf<String, Long>()

    data class CachedModel(
        val fileName: String,
        val asset: FilamentAsset,
        val buffer: ByteBuffer,
        val cachedAt: Long = System.currentTimeMillis()
    )

    /**
     * Gets a cached model or returns null if not cached
     */
    fun get(fileName: String): CachedModel? {
        val cached = cache[fileName]
        if (cached != null) {
            // Update access time for LRU
            accessOrder[fileName] = System.currentTimeMillis()
            Log.d(TAG, "Cache HIT for: $fileName")
        } else {
            Log.d(TAG, "Cache MISS for: $fileName")
        }
        return cached
    }

    /**
     * Caches a model with LRU eviction if needed
     */
    fun put(fileName: String, asset: FilamentAsset, buffer: ByteBuffer) {
        // Check if we need to evict
        if (cache.size >= MAX_CACHE_SIZE && !cache.containsKey(fileName)) {
            evictLRU()
        }

        cache[fileName] = CachedModel(fileName, asset, buffer)
        accessOrder[fileName] = System.currentTimeMillis()

        Log.d(TAG, "Cached model: $fileName (cache size: ${cache.size})")
    }

    /**
     * Evicts the least recently used model
     */
    private fun evictLRU() {
        val lruKey = accessOrder.minByOrNull { it.value }?.key ?: return

        cache.remove(lruKey)?.let { removed ->
            // Note: We don't destroy the asset here because it might still be in use
            // The caller should handle destruction
            Log.d(TAG, "Evicted LRU model: $lruKey")
        }
        accessOrder.remove(lruKey)
    }

    /**
     * Checks if a model is cached
     */
    fun contains(fileName: String): Boolean = cache.containsKey(fileName)

    /**
     * Clears all cached models
     */
    fun clear() {
        Log.d(TAG, "Clearing model cache (${cache.size} models)")
        cache.clear()
        accessOrder.clear()
    }

    /**
     * Gets cache statistics
     */
    fun getStats(): CacheStats {
        return CacheStats(
            size = cache.size,
            maxSize = MAX_CACHE_SIZE,
            models = cache.keys.toList()
        )
    }

    data class CacheStats(
        val size: Int,
        val maxSize: Int,
        val models: List<String>
    )
}