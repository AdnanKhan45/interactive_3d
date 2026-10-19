package com.example.interactive_3d.renderer

import android.util.Log
import com.google.android.filament.*
import com.google.android.filament.utils.KTX1Loader
import java.nio.ByteBuffer

/**
 * Manages environment lighting, skybox, and background color.
 *
 * Handles two lighting paths:
 * - **Default lighting**: Three directional lights (sun, fill, back) and a
 *   flat indirect light for models rendered before IBL loads.
 * - **IBL lighting**: Loaded from KTX files. The IBL and skybox load
 *   independently; the skybox is skipped when [useSolidBackground] is true.
 */
internal class EnvironmentLoader {

    private companion object {
        const val TAG = "EnvironmentLoader"
    }

    // Light entities (must be destroyed during cleanup)
    var sunlight: Int = 0; private set
    var fillLight: Int = 0; private set
    var backLight: Int = 0; private set

    var indirectLight: IndirectLight? = null; private set
    var skybox: Skybox? = null; private set
    private var iblCubemap: Texture? = null
    private var skyboxCubemap: Texture? = null
    var iblLoaded = false; private set

    // Solid background
    var useSolidBackground = false; private set
    var solidBackgroundColor = floatArrayOf(0.92f, 0.92f, 0.92f, 1.0f)
        private set

    /**
     * Creates three-point directional lighting and a flat indirect light
     * to ensure the model is visible before IBL data arrives.
     */
    fun setupDefaultLighting(engine: Engine, scene: Scene) {
        sunlight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 1.0f, 1.0f)
            .intensity(250_000.0f)
            .direction(0.0f, -1.0f, -0.3f)
            .castShadows(false)
            .build(engine, sunlight)
        scene.addEntity(sunlight)

        fillLight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(0.9f, 0.9f, 1.0f)
            .intensity(100_000.0f)
            .direction(1.0f, 0.0f, 0.0f)
            .castShadows(false)
            .build(engine, fillLight)
        scene.addEntity(fillLight)

        backLight = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1.0f, 1.0f, 0.9f)
            .intensity(80_000.0f)
            .direction(-0.5f, 0.5f, 1.0f)
            .castShadows(false)
            .build(engine, backLight)
        scene.addEntity(backLight)

        try {
            indirectLight = IndirectLight.Builder()
                .intensity(50_000.0f)
                .irradiance(3, floatArrayOf(
                    1.0f, 1.0f, 1.0f,
                    0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f,
                    0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f
                ))
                .build(engine)
            scene.indirectLight = indirectLight
        } catch (e: Exception) {
            Log.w(TAG, "Could not create fallback indirect light: ${e.message}")
        }
    }

    /**
     * Loads whichever of the IBL and skybox KTX buffers is given, replacing any
     * previous one. Returns true when an IBL was applied.
     */
    fun loadEnvironment(
        engine: Engine,
        scene: Scene,
        iblBuffer: ByteBuffer?,
        skyboxBuffer: ByteBuffer?
    ): Boolean {
        var iblApplied = false
        if (iblBuffer != null) {
            try {
                loadIbl(engine, scene, iblBuffer)
                iblApplied = true
            } catch (e: Exception) {
                Log.w(TAG, "Could not load IBL: ${e.message}")
            }
        }
        // A skybox would cover the solid clear color.
        if (skyboxBuffer != null && !useSolidBackground) {
            try { loadSkybox(engine, scene, skyboxBuffer) }
            catch (e: Exception) { Log.w(TAG, "Could not load skybox: ${e.message}") }
        }
        return iblApplied
    }

    private fun loadIbl(engine: Engine, scene: Scene, buffer: ByteBuffer) {
        buffer.rewind()
        val bundle = KTX1Loader.createIndirectLight(engine, buffer)
        val previous = indirectLight
        val previousCubemap = iblCubemap
        indirectLight = bundle.indirectLight?.apply { intensity = 50_000.0f }
        iblCubemap = bundle.cubemap
        scene.indirectLight = indirectLight
        previous?.let { engine.destroyIndirectLight(it) }
        previousCubemap?.let { engine.destroyTexture(it) }
        iblLoaded = true
    }

    private fun loadSkybox(engine: Engine, scene: Scene, buffer: ByteBuffer) {
        buffer.rewind()
        val bundle = KTX1Loader.createSkybox(engine, buffer)
        val previous = skybox
        val previousCubemap = skyboxCubemap
        skybox = bundle.skybox
        skyboxCubemap = bundle.cubemap
        scene.skybox = skybox
        previous?.let { engine.destroySkybox(it) }
        previousCubemap?.let { engine.destroyTexture(it) }
    }

    /**
     * Enables a solid-color background. The renderer's clear color is set
     * to [color] (RGBA 0.0–1.0) and any existing skybox is removed.
     */
    fun setBackgroundColor(color: List<Double>, renderer: Renderer, scene: Scene) {
        if (color.size < 3) return
        useSolidBackground = true
        solidBackgroundColor = floatArrayOf(
            color[0].toFloat(),
            color[1].toFloat(),
            color[2].toFloat(),
            if (color.size >= 4) color[3].toFloat() else 1.0f
        )
        applyClearColor(renderer)
        scene.skybox = null
    }

    /**
     * Sets the renderer's clear color based on current background settings.
     */
    fun applyClearColor(renderer: Renderer) {
        renderer.setClearOptions(
            Renderer.ClearOptions().apply {
                clearColor = if (useSolidBackground) solidBackgroundColor
                else floatArrayOf(0.2f, 0.2f, 0.2f, 1.0f)
                clear = true
            }
        )
    }

    /**
     * Destroys all lighting entities and environment resources.
     */
    fun cleanup(engine: Engine, scene: Scene) {
        scene.indirectLight = null
        scene.skybox = null

        listOf(sunlight, fillLight, backLight).filter { it != 0 }.forEach { entity ->
            scene.removeEntity(entity)
            engine.destroyEntity(entity)
            EntityManager.get().destroy(entity)
        }

        indirectLight?.let { engine.destroyIndirectLight(it) }
        skybox?.let { engine.destroySkybox(it) }
        iblCubemap?.let { engine.destroyTexture(it) }
        skyboxCubemap?.let { engine.destroyTexture(it) }

        indirectLight = null
        skybox = null
        iblCubemap = null
        skyboxCubemap = null
        sunlight = 0
        fillLight = 0
        backLight = 0
        iblLoaded = false
    }
}