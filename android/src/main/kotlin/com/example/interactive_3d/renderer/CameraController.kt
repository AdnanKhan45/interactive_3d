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
        private const val MIN_ZOOM = 0.5f
        // Pinch can zoom in far enough to look at details of tall models (was 3.0).
        private const val MAX_ZOOM = 10.0f
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
        boundsCenter = center.copyOf()
        boundsHalfExtent = halfExtent.copyOf()

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
     * Adds [delta] to the zoom level within the pinch range. A level already past
     * the range is never pushed further out, nor pulled back against [delta].
     */
    fun zoomBy(delta: Float) {
        zoomLevel = (zoomLevel + delta).coerceIn(
            minOf(zoomLevel, MIN_ZOOM), maxOf(zoomLevel, MAX_ZOOM)
        )
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
     * Handles a two-finger drag: moves the orbit target (and so the camera) in the
     * camera's screen plane, so the model follows the fingers. Deltas are in render
     * pixels, [viewportHeight] is the render height. Moves add up across gestures;
     * the target stays inside the model's bounding box, so the model cannot be lost.
     * Returns true if the camera was updated.
     */
    fun onTranslate(deltaX: Float, deltaY: Float, viewportHeight: Int): Boolean {
        if (viewportHeight <= 0) return false
        // No throttle here: a dropped event would lose its share of the drag (touch
        // events arrive every ~8 ms at 120 Hz), so the view would lag the fingers.
        // Moving the target is cheap. The shared throttle is not used either, since a
        // two-finger drag sends a scale event right before each translate.
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
        targetPosition = FloatArray(3) { i ->
            val r = if (i == 0) rx else if (i == 2) rz else 0f
            val u = if (i == 0) ux else if (i == 1) uy else uz
            (targetPosition[i] + r * moveRight + u * moveUp).coerceIn(
                boundsCenter[i] - boundsHalfExtent[i],
                boundsCenter[i] + boundsHalfExtent[i],
            )
        }
        return true
    }

    /**
     * Handles a pinch-to-zoom gesture. Returns true if the camera was updated.
     */
    /**
     * Handles a pinch: [scale] is the change since the previous event (not since
     * the gesture started), so holding the fingers still no longer keeps zooming.
     * Zoom both moves the camera closer and narrows the field of view, so the model
     * grows about with zoom²; the square root makes it follow the fingers 1:1.
     * Not throttled: a dropped event would lose its share of the pinch.
     */
    fun onScale(scale: Float): Boolean {
        if (scale <= 0f || !scale.isFinite()) return false
        markInteracting()
        zoomLevel = (zoomLevel * sqrt(scale)).coerceIn(MIN_ZOOM, MAX_ZOOM)
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

    private fun shouldUpdate(): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastCameraUpdate < THROTTLE_MS) return false
        lastCameraUpdate = now
        return true
    }
}