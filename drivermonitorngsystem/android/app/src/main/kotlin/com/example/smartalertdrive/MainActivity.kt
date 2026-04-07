package com.example.smartalertdrive

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.bantaydrive/pip"
    private val EVENT_CHANNEL  = "com.bantaydrive/pip_events"

    private var isRecording = false
    private var pipEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Method channel — Flutter calls native
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setRecording" -> {
                        isRecording = call.argument<Boolean>("isRecording") ?: false
                        result.success(null)
                    }
                    "enterPip" -> {
                        val isLandscape = call.argument<Boolean>("isLandscape") ?: false
                        val success = enterPipMode(isLandscape)
                        result.success(success)
                    }
                    else -> result.notImplemented()
                }
            }

        // Event channel — native pushes PiP state changes to Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    pipEventSink = sink
                }
                override fun onCancel(arguments: Any?) {
                    pipEventSink = null
                }
            })
    }

    // Called when user presses HOME button — enters PiP if recording
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isRecording) {
            val isLandscape = resources.configuration.orientation ==
                android.content.res.Configuration.ORIENTATION_LANDSCAPE
            enterPipMode(isLandscape)
        }
    }

    // Called by Android when PiP mode changes — reliably fires every time
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Push to Flutter via EventChannel — more reliable than MethodChannel invoke
        runOnUiThread {
            pipEventSink?.success(isInPictureInPictureMode)
        }
    }

    private fun enterPipMode(isLandscape: Boolean = false): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            // Dynamically match the aspect ratio to the device's current orientation
            // so the PiP window fills correctly whether the driver is using the phone
            // in portrait (9:16) or landscape (16:9) — e.g. when using Spotify landscape.
            val ratio = if (isLandscape) Rational(16, 9) else Rational(9, 16)
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(ratio)
                .build()
            enterPictureInPictureMode(params)
            true
        } catch (e: Exception) {
            false
        }
    }
}