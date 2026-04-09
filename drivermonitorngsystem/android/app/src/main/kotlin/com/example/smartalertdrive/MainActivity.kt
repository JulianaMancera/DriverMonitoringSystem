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
        runOnUiThread {
            pipEventSink?.success(isInPictureInPictureMode)
        }
    }

    // Called whenever the device rotates — including while already in PiP.
    // We update the PiP aspect ratio live so the window reshapes to match
    // the new orientation (portrait ↔ landscape) without needing to re-enter PiP.
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            isInPictureInPictureMode && isRecording) {
            try {
                val isLandscape = newConfig.orientation ==
                    Configuration.ORIENTATION_LANDSCAPE
                // 1. Reshape the PiP window to match new orientation
                val ratio = if (isLandscape) Rational(16, 9) else Rational(9, 16)
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(ratio)
                    .build()
                setPictureInPictureParams(params)
                // 2. Tell Flutter the new orientation so the camera preview
                //    SizedBox can swap its width/height dimensions to match.
                //    We reuse the existing EventChannel with a string prefix
                //    so Flutter can distinguish orientation events from pip events.
                runOnUiThread {
                    pipEventSink?.success(
                        if (isLandscape) "orientation:landscape"
                        else             "orientation:portrait"
                    )
                }
            } catch (e: Exception) {
                // Ignore — device may not support params update mid-PiP
            }
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