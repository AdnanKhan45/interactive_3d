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
 * - **IBL lighting**: Loaded from KTX files. IBL always loads for PBR quality;
 *   the skybox is conditionally skipped when [useSolidBackground] is true.
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
     * Loads IBL and skybox from KTX buffers.
     *
     * IBL always loads because it provides PBR-quality reflections and
     * ambient light. The skybox is skipped when [useSolidBackground] is set,
     * keeping the solid clear color visible behind the model.
     */
    fun loadEnvironment(
        engine: Engine,
        scene: Scene,
        iblBuffer: ByteBuffer,
        skyboxBuffer: ByteBuffer
    ) {
        // Replace the placeholder indirect light with the real IBL
        iblBuffer.rewind()
        val iblBundle = KTX1Loader.createIndirectLight(engine, iblBuffer)
        indirectLight?.let { engine.destroyIndirectLight(it) }
        indirectLight = iblBundle.indirectLight
        indirectLight?.intensity = 50_000.0f
        scene.indirectLight = indirectLight

        if (!useSolidBackground) {
            skyboxBuffer.rewind()
            val skyboxBundle = KTX1Loader.createSkybox(engine, skyboxBuffer)
            skybox = skyboxBundle.skybox
            scene.skybox = skybox
        }

        iblLoaded = true
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

        indirectLight = null
        skybox = null
        sunlight = 0
        fillLight = 0
        backLight = 0
        iblLoaded = false
    }
}