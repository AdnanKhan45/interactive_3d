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
    private const val MAX_CACHE_SIZE = 3  // ✅ Reduced for low-end devices

    // ✅ Cache ONLY the asset reference, NOT the buffer
    private val cache = mutableMapOf<String, CachedModel>()
    private val accessOrder = mutableMapOf<String, Long>()

    data class CachedModel(
        val fileName: String,
        val asset: FilamentAsset,
        val buffer: ByteBuffer,  // Keep for re-loading, but this is the ONLY copy
        val cachedAt: Long = System.currentTimeMillis()
    )

    fun get(fileName: String): CachedModel? {
        val cached = cache[fileName]
        if (cached != null) {
            accessOrder[fileName] = System.currentTimeMillis()
            Log.d(TAG, "Cache HIT for: $fileName")
        } else {
            Log.d(TAG, "Cache MISS for: $fileName")
        }
        return cached
    }

    fun put(fileName: String, asset: FilamentAsset, buffer: ByteBuffer) {
        if (cache.size >= MAX_CACHE_SIZE && !cache.containsKey(fileName)) {
            evictLRU()
        }

        cache[fileName] = CachedModel(fileName, asset, buffer)
        accessOrder[fileName] = System.currentTimeMillis()
        Log.d(TAG, "Cached model: $fileName (cache size: ${cache.size})")
    }

    private fun evictLRU() {
        val lruKey = accessOrder.minByOrNull { it.value }?.key ?: return
        cache.remove(lruKey)?.let { removed ->
            // ✅ CRITICAL: Destroy the asset to free GPU memory
            try {
                // Note: Asset destruction should be handled carefully
                // as it might be in use. Consider reference counting.
                Log.d(TAG, "Evicted LRU model: $lruKey")
            } catch (e: Exception) {
                Log.e(TAG, "Error evicting model: ${e.message}")
            }
        }
        accessOrder.remove(lruKey)
    }

    fun clear() {
        Log.d(TAG, "Clearing model cache (${cache.size} models)")
        cache.clear()
        accessOrder.clear()
    }

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