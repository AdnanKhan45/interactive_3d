package com.example.interactive_3d.renderer

import android.os.Handler
import android.os.Looper
import com.google.android.filament.Camera
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Controls the orbit camera around the 3D model.
 *
 * Uses spherical coordinates ([orbitAngleX], [orbitAngleY]) and a radius
 * derived from the model bounding box. Gesture input is not throttled, so no
 * part of a drag is lost; each event only updates the camera state.
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
        private const val MIN_ZOOM = 0.5f
        // zoomBy range, documented and matched by iOS.
        private const val MAX_ZOOM = 3.0f
        // Pinch goes further in, to look at details of large models.
        private const val MAX_PINCH_ZOOM = 10.0f
        // Thin axes get at least this share of the largest half-extent, so a
        // two-finger move on a flat model is not clipped to zero.
        private const val MIN_HALF_EXTENT_RATIO = 0.1f
        // Orbit radians per render pixel, set to keep the orbit speed of
        // earlier releases now that no move is dropped.
        private const val ORBIT_RADIANS_PER_PIXEL = 0.01f
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

    // Model bounds, used to keep a translated target inside the model.
    private var boundsCenter = floatArrayOf(0f, 0f, 0f)
    private var boundsHalfExtent = floatArrayOf(0f, 0f, 0f)

    // Adaptive frame pacing
    var isInteracting = false
        private set
    var idleFrameCount = 0
    // True until a frame is drawn after the latest change; keeps the loop from idling first.
    var pendingDraw = false

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
        boundsCenter = center.copyOf()
        val maxExtent = maxOf(halfExtent[0], halfExtent[1], halfExtent[2])
        boundsHalfExtent = FloatArray(3) { i ->
            maxOf(halfExtent[i], maxExtent * MIN_HALF_EXTENT_RATIO)
        }
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
     * Adds [delta] to the zoom level within MIN_ZOOM..MAX_ZOOM. A level already past
     * the range is never pushed further out, nor pulled back against [delta].
     */
    fun zoomBy(delta: Float) {
        zoomLevel = (zoomLevel + delta).coerceIn(
            minOf(zoomLevel, MIN_ZOOM), maxOf(zoomLevel, MAX_ZOOM)
        )
    }

    /**
     * Handles a one-finger orbit. Not throttled: Dart only sends a delta once it
     * has added up, so a dropped event would be lost.
     */
    fun onPan(deltaX: Float, deltaY: Float): Boolean {
        markInteracting()

        orbitAngleY -= deltaX * ORBIT_RADIANS_PER_PIXEL
        orbitAngleX += deltaY * ORBIT_RADIANS_PER_PIXEL
        orbitAngleX = orbitAngleX.coerceIn(-1.4f, 1.4f)
        return true
    }

    /**
     * Handles a two-finger drag: moves the orbit target in the camera plane so the
     * model follows the fingers, kept inside the model bounds. Deltas are in render
     * pixels, [viewportHeight] is the render height. Not throttled, like [onPan].
     */
    fun onTranslate(deltaX: Float, deltaY: Float, viewportHeight: Int): Boolean {
        if (viewportHeight <= 0) return false
        markInteracting()

        // World units covered by one pixel at the target's distance.
        val distance = orbitRadius / zoomLevel
        val fov = Math.toRadians(DEFAULT_FOV / zoomLevel)
        val worldPerPixel = (2.0 * distance * tan(fov / 2.0) / viewportHeight).toFloat()

        // Camera axes from the orbit angles: forward points from the eye to the target.
        val fx = -(cos(orbitAngleX) * sin(orbitAngleY))
        val fy = -sin(orbitAngleX)
        val fz = -(cos(orbitAngleX) * cos(orbitAngleY))
        // right = forward x worldUp, up = right x forward
        var rx = -fz
        var rz = fx
        val rLen = sqrt(rx * rx + rz * rz)
        if (rLen < 1e-6f) return false
        rx /= rLen
        rz /= rLen
        val ux = -rz * fy
        val uy = rz * fx - rx * fz
        val uz = rx * fy

        // The content follows the fingers, so the target moves the other way.
        val moveRight = -deltaX * worldPerPixel
        val moveUp = deltaY * worldPerPixel
        val rightPart = floatArrayOf(rx * moveRight, 0f, rz * moveRight)
        val upPart = floatArrayOf(ux * moveUp, uy * moveUp, uz * moveUp)
        val fullMove = FloatArray(3) { i -> rightPart[i] + upPart[i] }

        // If a bound shortens the full move, sliding along just up or right may go
        // further: keep the longest. All three stay in the camera plane.
        val applied = listOf(fullMove, upPart, rightPart)
            .map { clipMove(it) }
            .maxByOrNull { it[0] * it[0] + it[1] * it[1] + it[2] * it[2] }
            ?: return false
        targetPosition = FloatArray(3) { i -> targetPosition[i] + applied[i] }
        return true
    }

    /**
     * Shortens [move] by one factor in 0..1 so the target stays inside the model
     * bounds, keeping its direction (and so the camera plane). Clamping each axis
     * would bend it and add depth. Axes already outside can only move back in.
     */
    private fun clipMove(move: FloatArray): FloatArray {
        var scale = 1f
        for (i in 0..2) {
            if (move[i] == 0f) continue
            val limit = boundsCenter[i] +
                if (move[i] > 0f) boundsHalfExtent[i] else -boundsHalfExtent[i]
            scale = minOf(scale, maxOf((limit - targetPosition[i]) / move[i], 0f))
        }
        return FloatArray(3) { i -> move[i] * scale }
    }

    /**
     * Handles a pinch step: [scale] is the change since the previous event. Zoom
     * both moves closer and narrows the field of view, so the model grows with
     * zoom²; the square root makes it follow the fingers. Not throttled.
     */
    fun onScale(scale: Float): Boolean {
        if (scale <= 0f || !scale.isFinite()) return false
        markInteracting()
        zoomLevel = (zoomLevel * sqrt(scale)).coerceIn(MIN_ZOOM, MAX_PINCH_ZOOM)
        return true
    }

    /**
     * Marks the viewport as actively being touched. Call on tap, pan, or
     * scale start. The idle timeout resets each time.
     */
    fun markInteracting() {
        isInteracting = true
        idleFrameCount = 0
        pendingDraw = true
        idleHandler.removeCallbacks(markIdleRunnable)
        idleHandler.postDelayed(markIdleRunnable, 500)
    }

    /**
     * Cancels any pending idle callbacks. Call during cleanup.
     */
    fun cancelCallbacks() {
        idleHandler.removeCallbacks(markIdleRunnable)
    }
}