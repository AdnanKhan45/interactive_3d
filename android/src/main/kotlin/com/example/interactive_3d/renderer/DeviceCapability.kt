package com.example.interactive_3d.renderer

import android.app.ActivityManager
import android.content.Context
import android.util.Log

/**
 * Detects hardware capabilities and provides per-tier rendering settings.
 *
 * Devices are classified into three tiers based on total RAM and GPU model.
 * Each tier maps to a [QualitySettings] instance that controls MSAA sample
 * count, bloom, and ambient occlusion. The renderer reads these at startup
 * and adjusts Filament's view options accordingly.
 */
internal object DeviceCapability {

    private const val TAG = "DeviceCapability"

    enum class Tier { LOW_END, MID_RANGE, HIGH_END }

    data class QualitySettings(
        val msaaSamples: Int,
        val enableBloom: Boolean,
        val enableAO: Boolean
    )

    /**
     * Classifies the current device.
     */
    fun detectTier(context: Context): Tier {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        val totalRamGB = memoryInfo.totalMem / (1024 * 1024 * 1024)

        return try {
            val gpu = android.opengl.GLES20.glGetString(android.opengl.GLES20.GL_RENDERER) ?: ""
            Log.d(TAG, "GPU: $gpu, RAM: ${totalRamGB}GB")

            when {
                totalRamGB >= 8 && (
                    gpu.contains("Adreno 6") ||
                        gpu.contains("Mali-G7") ||
                        gpu.contains("Mali-G8")
                    ) -> Tier.HIGH_END

                totalRamGB >= 4 -> Tier.MID_RANGE

                else -> Tier.LOW_END
            }
        } catch (e: Exception) {
            Log.w(TAG, "GPU detection failed, defaulting to MID_RANGE: ${e.message}")
            Tier.MID_RANGE
        }
    }

    /**
     * Returns rendering quality settings for the given [tier].
     */
    fun settingsFor(tier: Tier): QualitySettings {
        return when (tier) {
            Tier.HIGH_END -> QualitySettings(
                msaaSamples = 4,
                enableBloom = true,
                enableAO = true
            )
            Tier.MID_RANGE -> QualitySettings(
                msaaSamples = 2,
                enableBloom = false,
                enableAO = false
            )
            Tier.LOW_END -> QualitySettings(
                msaaSamples = 2,
                enableBloom = false,
                enableAO = false
            )
        }
    }

    /**
     * Supersampling multiplier per tier.
     */
    fun renderScaleFor(tier: Tier): Float {
        return when (tier) {
            Tier.HIGH_END -> 1.5f
            Tier.MID_RANGE -> 1.25f
            Tier.LOW_END -> 1.1f
        }
    }
}