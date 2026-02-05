import Foundation
import SceneKit

class Interactive3DCacheManager {
    private let cacheKey: String
    private let userDefaults: UserDefaults
    private let cacheColor: UIColor

    // Store the cached entity names (can be IDs if you prefer)
    private(set) var cachedEntities: Set<String> = []

    // A closure to notify when cache changes
    var onCacheChanged: ((Set<String>) -> Void)?

    init(modelKey: String, cacheColor: UIColor, userDefaults: UserDefaults = .standard) {
        self.cacheKey = "interactive3d.cache.\(modelKey)"
        self.userDefaults = userDefaults
        self.cacheColor = cacheColor
        loadCache()
    }

    // Loads cache from persistent storage
    private func loadCache() {
        if let cached = userDefaults.array(forKey: cacheKey) as? [String] {
            cachedEntities = Set(cached)
        } else {
            cachedEntities = []
        }
    }

    // Persists cache to disk
    private func saveCache() {
        userDefaults.set(Array(cachedEntities), forKey: cacheKey)
        // Note: synchronize() is deprecated and no longer needed in modern iOS
        // UserDefaults automatically synchronizes periodically
        onCacheChanged?(cachedEntities)
    }

    // Adds entity to cache
    func addToCache(_ entity: String) {
        cachedEntities.insert(entity)
        saveCache()
    }

    // Removes entity from cache
    func removeFromCache(_ entity: String) {
        cachedEntities.remove(entity)
        saveCache()
    }

    // Clears the entire cache for this model
    func clearCache() {
        cachedEntities.removeAll()
        userDefaults.removeObject(forKey: cacheKey)
        // Note: synchronize() is deprecated and no longer needed
        onCacheChanged?(cachedEntities)
    }

    // For coloring: Returns true if an entity is cached
    func isCached(_ entity: String) -> Bool {
        return cachedEntities.contains(entity)
    }
}
