package com.example.interactive_3d.renderer

import android.os.Handler
import android.os.Looper
import com.google.android.filament.Camera
import kotlin.math.cos
import kotlin.math.sin

/**
 * Controls the orbit camera around the 3D model.
 *
 * Uses spherical coordinates ([orbitAngleX], [orbitAngleY]) and a radius
 * derived from the model bounding box. Gesture input is throttled to avoid
 * overloading the GPU with redundant projection updates.
 *
 * Also manages adaptive frame pacing state: [isInteracting] tracks whether
 * the user is actively touching the viewport. The render loop reads this
 * flag to throttle frame rate when idle (see [FrameCallback] in the renderer).
 */
internal class CameraController {

    companion object {
        private const val DEFAULT_FOV = 45.0
        private const val NEAR_PLANE = 0.001
        private const val FAR_PLANE = 1000.0
        private const val THROTTLE_MS = 8L
    }

    // Spherical orbit state
    var orbitRadius = 5.0f
        private set
    var orbitAngleX = 0.3f
        private set
    var orbitAngleY = 0.5f
        private set
    var targetPosition = floatArrayOf(0f, 0f, 0f)
        private set
    var zoomLevel = 1.0f
        private set

    // Adaptive frame pacing
    var isInteracting = false
        private set
    var idleFrameCount = 0

    private var lastCameraUpdate = 0L
    private val idleHandler = Handler(Looper.getMainLooper())
    private val markIdleRunnable = Runnable {
        isInteracting = false
        idleFrameCount = 0
    }

    val fov: Double get() = DEFAULT_FOV
    val nearPlane: Double get() = NEAR_PLANE
    val farPlane: Double get() = FAR_PLANE

    /**
     * Applies the current spherical coordinates to the Filament [camera].
     */
    fun applyToCamera(camera: Camera) {
        val radius = orbitRadius / zoomLevel
        val x = radius * cos(orbitAngleX.toDouble()) * sin(orbitAngleY.toDouble())
        val y = radius * sin(orbitAngleX.toDouble())
        val z = radius * cos(orbitAngleX.toDouble()) * cos(orbitAngleY.toDouble())

        camera.lookAt(
            x + targetPosition[0].toDouble(),
            y + targetPosition[1].toDouble(),
            z + targetPosition[2].toDouble(),
            targetPosition[0].toDouble(),
            targetPosition[1].toDouble(),
            targetPosition[2].toDouble(),
            0.0, 1.0, 0.0
        )
    }

    /**
     * Sets up the perspective projection on [camera] for the given viewport.
     */
    fun applyProjection(camera: Camera, width: Int, height: Int) {
        camera.setProjection(
            DEFAULT_FOV / zoomLevel,
            if (height > 0) width.toDouble() / height.toDouble() else 1.0,
            NEAR_PLANE,
            FAR_PLANE,
            Camera.Fov.VERTICAL
        )
    }

    /**
     * Positions the camera to frame the model based on its bounding box.
     *
     * The model is normalized so it fills roughly 70% of the viewport regardless
     * of its real-world dimensions. [center] and [halfExtent] come from the
     * Filament asset bounding box.
     */
    fun fitToBoundingBox(center: FloatArray, halfExtent: FloatArray) {
        targetPosition = floatArrayOf(center[0], center[1], center[2])

        val maxExtent = maxOf(halfExtent[0], halfExtent[1], halfExtent[2])
        val targetWorldSize = 2.0f
        val normalizedScale = if (maxExtent > 0) targetWorldSize / maxExtent else 1.0f

        val fovRadians = Math.toRadians(DEFAULT_FOV)
        val fitDistance = targetWorldSize / Math.tan(fovRadians / 8.0).toFloat()
        orbitRadius = (fitDistance * 1.4f) / normalizedScale

        orbitAngleX = 0.0f
        orbitAngleY = 0.0f
    }

    /**
     * Sets the zoom level directly (e.g. from the public API).
     */
    fun setZoom(zoom: Float) {
        if (zoom <= 0) return
        zoomLevel = zoom
    }

    /**
     * Handles a pan gesture. Returns true if the camera was updated,
     * false if the update was throttled.
     */
    fun onPan(deltaX: Float, deltaY: Float): Boolean {
        if (!shouldUpdate()) return false
        markInteracting()

        orbitAngleY -= deltaX * 0.02f
        orbitAngleX += deltaY * 0.02f
        orbitAngleX = orbitAngleX.coerceIn(-1.4f, 1.4f)
        return true
    }

    /**
     * Handles a pinch-to-zoom gesture. Returns true if the camera was updated.
     */
    fun onScale(scale: Float): Boolean {
        if (!shouldUpdate()) return false
        markInteracting()

        val factor = if (scale > 1.0f) {
            1.0f + (scale - 1.0f) * 0.15f
        } else {
            1.0f - (1.0f - scale) * 0.15f
        }
        zoomLevel = (zoomLevel * factor).coerceIn(0.5f, 3.0f)
        return true
    }

    /**
     * Marks the viewport as actively being touched. Call on tap, pan, or
     * scale start. The idle timeout resets each time.
     */
    fun markInteracting() {
        isInteracting = true
        idleFrameCount = 0
        idleHandler.removeCallbacks(markIdleRunnable)
        idleHandler.postDelayed(markIdleRunnable, 500)
    }

    /**
     * Cancels any pending idle callbacks. Call during cleanup.
     */
    fun cancelCallbacks() {
        idleHandler.removeCallbacks(markIdleRunnable)
    }

    private fun shouldUpdate(): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastCameraUpdate < THROTTLE_MS) return false
        lastCameraUpdate = now
        return true
    }
}