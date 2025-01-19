package com.example.interactive_3d

import android.app.Activity
import android.content.Context
import android.content.MutableContextWrapper
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.nio.ByteBuffer
import java.util.concurrent.Executor
import com.google.android.filament.utils.Utils

class Interactive3dPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    id: Int
) : PlatformView, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var customView: ModelView
    private var eventSink: EventChannel.EventSink? = null
    private val methodChannel = MethodChannel(messenger, "interactive_3d_$id")
    private val eventChannel = EventChannel(messenger, "interactive_3d_events_$id")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { command ->
        mainHandler.post(command)
    }

    init {
        val v = (context as MutableContextWrapper).baseContext as Activity
        customView = ModelView(v)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)

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

    companion object {
        init {
            Utils.init()
        }

        private const val TAG = "Interactive3d"
    }

    override fun getView(): ModelView {
        return customView
    }

    override fun dispose() {
        Log.e(TAG, "dispose: PlatformView Dispose")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.e(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "loadModel" -> {
                val modelBytes = call.argument<ByteArray>("modelBytes")
                if (modelBytes != null) {
                    val buffer = ByteBuffer.wrap(modelBytes)
                    mainHandler.post {
                        customView.setModel(buffer)
                        result.success(null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "modelBytes is null", null)
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

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

}
