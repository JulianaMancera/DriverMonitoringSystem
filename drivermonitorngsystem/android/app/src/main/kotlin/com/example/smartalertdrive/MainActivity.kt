package com.example.smartalertdrive

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.graphics.Rect
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
    private var isInPip     = false
    private var pipEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

                    // ── NEW: called by Flutter after stop_recording to close PiP ──
                    // On all Android devices, the only reliable way to exit PiP
                    // programmatically is to move the task to back then relaunch,
                    // or use the moveTaskToBack approach. The simplest cross-device
                    // method is to call moveTaskToBack(false) which minimises the
                    // PiP window without killing the app.
                    "exitPip" -> {
                        if (isInPip) {
                            // Setting isRecording false first prevents re-entering PiP
                            // in onUserLeaveHint if the system briefly re-focuses us
                            isRecording = false
                            // Move app to back — Android automatically collapses the
                            // PiP window when the backing activity is no longer active
                            moveTaskToBack(false)
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    pipEventSink = sink
                    // Send current PiP state immediately when Flutter reconnects
                    sink?.success(mapOf("type" to "pip", "value" to isInPip))
                }
                override fun onCancel(arguments: Any?) {
                    pipEventSink = null
                }
            })
    }

    // ── Home button / recents pressed ─────────────────────────────────────────
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isRecording && !isInPip) {
            val isLandscape = resources.configuration.orientation ==
                Configuration.ORIENTATION_LANDSCAPE
            enterPipMode(isLandscape)
        }
    }

    // ── Back pressed ──────────────────────────────────────────────────────────
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (isInPip) {
            // Already in PiP — let system handle back (exits PiP)
            super.onBackPressed()
            return
        }
        if (isRecording && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val isLandscape = resources.configuration.orientation ==
                Configuration.ORIENTATION_LANDSCAPE
            val entered = enterPipMode(isLandscape)
            if (entered) return
        }
        super.onBackPressed()
    }

    // ── PiP state changed ─────────────────────────────────────────────────────
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        isInPip = isInPictureInPictureMode

        runOnUiThread {
            // Send PiP state change to Flutter
            pipEventSink?.success(
                mapOf("type" to "pip", "value" to isInPictureInPictureMode)
            )
            // Send orientation so camera preview adjusts dimensions
            val ori = if (newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE)
                "landscape" else "portrait"
            pipEventSink?.success(
                mapOf("type" to "orientation", "value" to ori)
            )
        }
    }

    // ── Device rotates ────────────────────────────────────────────────────────
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val isLandscape = newConfig.orientation ==
                    Configuration.ORIENTATION_LANDSCAPE
                if (isInPip && isRecording) {
                    val ratio = if (isLandscape) Rational(16, 9) else Rational(9, 16)
                    setPictureInPictureParams(
                        PictureInPictureParams.Builder()
                            .setAspectRatio(ratio)
                            .build()
                    )
                }
                if (isInPip) {
                    runOnUiThread {
                        pipEventSink?.success(
                            mapOf(
                                "type"  to "orientation",
                                "value" to if (isLandscape) "landscape" else "portrait"
                            )
                        )
                    }
                }
            } catch (_: Exception) { }
        }
    }

    // ── Enter PiP ─────────────────────────────────────────────────────────────
    private fun enterPipMode(isLandscape: Boolean = false): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val ratio   = if (isLandscape) Rational(16, 9) else Rational(9, 16)
            val builder = PictureInPictureParams.Builder().setAspectRatio(ratio)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val dm   = resources.displayMetrics
                val w    = dm.widthPixels
                val h    = dm.heightPixels
                val hint = if (isLandscape)
                    Rect(0, 0, w, h)
                else
                    Rect(0, 0, w, (h * 0.42f).toInt())
                builder.setSourceRectHint(hint)
                builder.setSeamlessResizeEnabled(false)
            }

            enterPictureInPictureMode(builder.build())
            true
        } catch (e: Exception) {
            false
        }
    }
}