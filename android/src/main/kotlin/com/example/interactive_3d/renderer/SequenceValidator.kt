package com.example.interactive_3d.renderer

/**
 * Validates whether a tap on a named entity is allowed based on
 * ordered selection rules.
 *
 * When the user provides selection sequence entries, taps are constrained
 * so entities within a group can only be selected in the defined order.
 * Bidirectional configs allow selection in either direction from the
 * current position. Tied groups enforce matching indices across groups.
 *
 * Mirrors iOS SequenceValidator.swift behavior. Validation is active
 * whenever [configs] is non-empty; nodes outside any configured group
 * are always allowed.
 */
internal class SequenceValidator {

    data class Config(
        val group: String,
        val order: List<String>,
        val bidirectional: Boolean,
        val tiedGroup: String?
    )

    var configs: List<Config> = emptyList()
        private set

    private val allowedNext = mutableMapOf<String, MutableSet<String>>()

    /** Parses sequence configs from the Flutter method call arguments. */
    fun configure(array: List<Map<String, Any>>) {
        configs = array.mapNotNull { dict ->
            val group = dict["group"] as? String ?: return@mapNotNull null
            @Suppress("UNCHECKED_CAST")
            val order = dict["order"] as? List<String> ?: return@mapNotNull null
            val bidirectional = dict["bidirectional"] as? Boolean ?: return@mapNotNull null
            Config(
                group = group,
                order = order,
                bidirectional = bidirectional,
                tiedGroup = dict["tiedGroup"] as? String
            )
        }
        buildMaps()
    }

    /** Resets all sequence state. */
    fun reset() {
        configs = emptyList()
        allowedNext.clear()
    }

    /**
     * Returns true if [nodeName] is allowed to be tapped given the current
     * set of [selectedNames].
     *
     * Rules:
     * - Deselecting (tapping an already selected node) is always allowed.
     * - Nodes not in any sequence are always allowed.
     * - First pick in a group is free, unless a tied group has started
     *   (then the matching index must be selected).
     * - Subsequent picks must be adjacent via the forward (and optionally
     *   backward) adjacency map.
     */
    fun isTapAllowed(nodeName: String, selectedNames: Set<String>): Boolean {
        // Deselecting is always allowed
        if (selectedNames.contains(nodeName)) return true

        val config = configs.firstOrNull { it.order.contains(nodeName) }
            ?: return true // not part of any sequence
        val idx = config.order.indexOf(nodeName)

        val selectedInGroup = selectedNames.filter { config.order.contains(it) }

        var selectedInTied: List<String> = emptyList()
        val tiedConfig = config.tiedGroup?.let { tiedName ->
            configs.firstOrNull { it.group == tiedName }
        }
        if (tiedConfig != null) {
            selectedInTied = selectedNames.filter { tiedConfig.order.contains(it) }
        }

        // Group hasn't started yet
        if (selectedInGroup.isEmpty()) {
            if (selectedInTied.isNotEmpty() && tiedConfig != null) {
                val requiredNode = tiedConfig.order[idx]
                return selectedInTied.contains(requiredNode)
            }
            return true
        }

        // Once started, only adjacent nodes are allowed
        for (name in selectedInGroup) {
            if (allowedNext[name]?.contains(nodeName) == true) return true
        }

        return false
    }

    private fun buildMaps() {
        allowedNext.clear()
        for (config in configs) {
            val list = config.order
            for (i in 0 until list.size - 1) {
                val name = list[i]
                val nextName = list[i + 1]
                allowedNext.getOrPut(name) { mutableSetOf() }.add(nextName)
                if (config.bidirectional) {
                    allowedNext.getOrPut(nextName) { mutableSetOf() }.add(name)
                }
            }
        }
    }
}
