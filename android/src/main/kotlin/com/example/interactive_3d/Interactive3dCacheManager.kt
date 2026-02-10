package com.example.interactive_3d

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

/**
 * Manages persistent caching of selected entities across sessions.
 */
class Interactive3dCacheManager(
    private val context: Context,
    private val modelKey: String,
    val cacheColor: FloatArray
) {
    companion object {
        private const val TAG = "Interactive3dCache"
        private const val PREFS_NAME = "interactive_3d_cache"
        private const val KEY_PREFIX = "cached_entities_"
    }

    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * Set of currently cached entity names for this model.
     */
    val cachedEntities: MutableSet<String> = mutableSetOf()

    init {
        loadFromPrefs()
    }

    /**
     * Loads cached entities from SharedPreferences.
     */
    private fun loadFromPrefs() {
        val key = KEY_PREFIX + modelKey
        val stored = prefs.getStringSet(key, emptySet()) ?: emptySet()
        cachedEntities.clear()
        cachedEntities.addAll(stored)
        Log.d(TAG, "Loaded ${cachedEntities.size} cached entities for model: $modelKey")
    }

    /**
     * Saves cached entities to SharedPreferences.
     */
    private fun saveToPrefs() {
        val key = KEY_PREFIX + modelKey
        prefs.edit().putStringSet(key, cachedEntities.toSet()).apply()
    }

    /**
     * Adds an entity to the cache.
     */
    fun addToCache(entityName: String) {
        if (cachedEntities.add(entityName)) {
            saveToPrefs()
            Log.d(TAG, "Added to cache: $entityName")
        }
    }

    /**
     * Removes an entity from the cache.
     */
    fun removeFromCache(entityName: String) {
        if (cachedEntities.remove(entityName)) {
            saveToPrefs()
            Log.d(TAG, "Removed from cache: $entityName")
        }
    }

    /**
     * Checks if an entity is cached.
     */
    fun isCached(entityName: String): Boolean {
        return cachedEntities.contains(entityName)
    }

    /**
     * Clears all cached entities for this model.
     */
    fun clearCache() {
        cachedEntities.clear()
        saveToPrefs()
        Log.d(TAG, "Cache cleared for model: $modelKey")
    }

    /**
     * Clears cache for all models.
     */
    fun clearAllCaches() {
        prefs.edit().clear().apply()
        cachedEntities.clear()
        Log.d(TAG, "All caches cleared")
    }
}