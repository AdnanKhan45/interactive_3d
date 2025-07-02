package com.example.interactive_3d

import android.content.Context
import android.content.SharedPreferences

class Interactive3dCacheManager(
    context: Context,
    modelKey: String,
    val cacheColor: FloatArray // RGBA
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("interactive3d_cache", Context.MODE_PRIVATE)
    private val cacheKey = "interactive3d.cache.$modelKey"

    // Keep cached entities in memory for quick access
    var cachedEntities: MutableSet<String> = mutableSetOf()
        private set

    // Callback for cache changes
    var onCacheChanged: ((Set<String>) -> Unit)? = null

    init {
        loadCache()
    }

    private fun loadCache() {
        cachedEntities = prefs.getStringSet(cacheKey, emptySet())?.toMutableSet() ?: mutableSetOf()
    }

    private fun saveCache() {
        prefs.edit().putStringSet(cacheKey, cachedEntities).apply()
        onCacheChanged?.invoke(cachedEntities)
    }

    fun addToCache(entity: String) {
        cachedEntities.add(entity)
        saveCache()
    }

    fun removeFromCache(entity: String) {
        cachedEntities.remove(entity)
        saveCache()
    }

    fun clearCache() {
        cachedEntities.clear()
        prefs.edit().remove(cacheKey).apply()
        onCacheChanged?.invoke(cachedEntities)
    }

    fun isCached(entity: String): Boolean {
        return cachedEntities.contains(entity)
    }
}
