package com.example.interactive_3d

import android.app.Activity
import android.content.Context
import android.content.MutableContextWrapper
import android.os.Handler
import android.os.Looper
import com.google.android.filament.utils.Utils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.nio.ByteBuffer
import java.util.concurrent.Executor

class Interactive3dPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    id: Int
) : PlatformView, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    // This is the view that will be returned to Flutter
    private var customView: ModelView
    // These are channels that will be used to communicate with Flutter
    private var eventSink: EventChannel.EventSink? = null
    private val methodChannel = MethodChannel(messenger, "interactive_3d_$id")
    private val eventChannel = EventChannel(messenger, "interactive_3d_events_$id")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { command ->
        mainHandler.post(command)
    }

    init {
        // Workaround to get the activity from the context
        val v = (context as MutableContextWrapper).baseContext as Activity
        // Initialize the custom view
        customView = ModelView(v)

        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)

        // Set the selection listener
        customView.setSelectionListener(object : ModelView.SelectionListener {
            override fun onSelectionChanged(selectedEntities: List<Map<String, Any>>) {
                // Now you can use eventSink?.success here
                mainHandler.post {
                    eventSink?.success(
                        mapOf(
                            "event" to "selectionChanged",
                            "selectedEntities" to selectedEntities
                        )
                    )
                }
            }
        })
    }

    // This is the main handler that will be used to post tasks to the main thread
    companion object {
        init {
            Utils.init()
        }

        private const val TAG = "Interactive3d"
    }

    // This method is called when Flutter requests the view
    override fun getView(): ModelView {
        return customView
    }

    // This method is called when the view is destroyed
    override fun dispose() {}

    // This method is called when Flutter sends a message to the platform
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> {
                val modelBytes = call.argument<ByteArray>("modelBytes")
                val modelName = call.argument<String>("name")
                val resources = call.argument<Map<String, ByteArray>>("resources") ?: emptyMap()
                val preselectedEntities = call.argument<List<String>?>("preselectedEntities")
                val selectionColor = call.argument<List<Double>?>("selectionColor")
                val patchColors = call.argument<List<Map<String, Any>>>("patchColors") // Receive patchColors

                if (modelBytes != null && modelName != null) {
                    val buffer = ByteBuffer.wrap(modelBytes)
                    mainHandler.post {
                        customView.setModel(buffer, modelName, resources, preselectedEntities, selectionColor, patchColors)
                        result.success(null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "modelBytes or modelName is null", null)
                }
            }

            "loadEnvironment" -> {
                val iblBytes = call.argument<ByteArray>("iblBytes")
                val skyboxBytes = call.argument<ByteArray>("skyboxBytes")
                if (iblBytes != null && skyboxBytes != null) {
                    val iblBuffer = ByteBuffer.wrap(iblBytes)
                    val skyboxBuffer = ByteBuffer.wrap(skyboxBytes)
                    mainHandler.post {
                        customView.setLights(skyboxBuffer, iblBuffer)
                        customView.setViewOptions()
                        result.success(null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "Environment bytes are null", null)
                }
            }
            "setZoomLevel" -> {
                val zoom = call.argument<Double>("zoom")?.toFloat()
                if (zoom != null) {
                    mainHandler.post {
                        customView.setCameraZoomLevel(zoom)
                        result.success(null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "Zoom value is null", null)
                }
            }
            "setPartGroupVisibility" -> {
                val group = call.argument<Map<String, Any>>("group")
                val visibility = call.argument<Map<String, Boolean>>("visibility")
                val title = group?.get("title") as? String
                val isVisible = visibility?.get(title) as? Boolean

                if (group != null && title != null && isVisible != null) {
                    mainHandler.post {
                        customView.setPartGroupVisibility(group, isVisible)
                        result.success(null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "Invalid group or visibility data", null)
                }
            }
            "unselectEntities" -> {
                val entityIds = call.argument<List<Long>?>("entityIds")
                mainHandler.post {
                    customView.unselectEntities(entityIds)
                    result.success(null)
                }
            }

            else -> result.notImplemented()
        }
    }

    // This method is called when Flutter listens to the event channel
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    // This method is called when Flutter cancels the event channel
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}