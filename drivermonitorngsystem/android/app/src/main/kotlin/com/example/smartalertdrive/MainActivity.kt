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

    private var isRecording    = false
    private var isInPip        = false
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
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    pipEventSink = sink
                    // FIX: Send current PiP state immediately when Flutter
                    // reconnects to the event channel (e.g. after hot reload or
                    // app resume). Prevents Flutter from being out of sync with
                    // the actual native PiP state.
                    sink?.success(mapOf("type" to "pip", "value" to isInPip))
                }
                override fun onCancel(arguments: Any?) {
                    pipEventSink = null
                }
            })
    }

    // ── Home button pressed ───────────────────────────────────────────────────
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isRecording && !isInPip) {
            val isLandscape = resources.configuration.orientation ==
                Configuration.ORIENTATION_LANDSCAPE
            enterPipMode(isLandscape)
        }
    }

    // ── Back pressed while recording → PiP instead of closing ────────────────
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (isRecording && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val isLandscape = resources.configuration.orientation ==
                Configuration.ORIENTATION_LANDSCAPE
            val entered = enterPipMode(isLandscape)
            if (entered) return
        }
        super.onBackPressed()
    }

    // ── PiP state changed ─────────────────────────────────────────────────────
    // FIX: Track isInPip natively so onUserLeaveHint doesn't try to enter PiP
    // when already in PiP (caused the "PiP disappears" bug — double-entering
    // PiP on some devices causes the window to collapse).
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        isInPip = isInPictureInPictureMode

        runOnUiThread {
            // Send PiP state change
            pipEventSink?.success(
                mapOf("type" to "pip", "value" to isInPictureInPictureMode)
            )

            // FIX: Send orientation immediately on PiP entry AND exit.
            // Previously only sent on entry — returning from PiP in landscape
            // left Flutter thinking orientation was still 'landscape' from PiP,
            // causing the camera preview to use wrong dimensions.
            val ori = if (newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE)
                "landscape" else "portrait"
            pipEventSink?.success(
                mapOf("type" to "orientation", "value" to ori)
            )
        }
    }

    // ── Device rotates while in PiP ───────────────────────────────────────────
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)

        // FIX: Update aspect ratio on rotation regardless of PiP state.
        // Previously guarded by isInPip — but if the flag was stale (race
        // between onPictureInPictureModeChanged and onConfigurationChanged),
        // the ratio update was skipped, leaving PiP in wrong aspect ratio.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val isLandscape = newConfig.orientation ==
                    Configuration.ORIENTATION_LANDSCAPE

                if (isInPip && isRecording) {
                    // Update aspect ratio while in PiP
                    val ratio = if (isLandscape) Rational(16, 9) else Rational(9, 16)
                    setPictureInPictureParams(
                        PictureInPictureParams.Builder()
                            .setAspectRatio(ratio)
                            .build()
                    )
                }

                // Always send orientation update so Flutter camera preview
                // can adjust dimensions correctly
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

            // FIX: setSourceRectHint tells Android WHICH part of the screen
            // to animate into the PiP window. Without this, Android zooms the
            // entire Flutter screen — causing the "full screen shown in PiP" bug.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val dm   = resources.displayMetrics
                val w    = dm.widthPixels
                val h    = dm.heightPixels
                // Portrait: hint = top 42% of screen (camera card area)
                // Landscape: hint = full screen (camera fills entire landscape)
                val hint = if (isLandscape)
                    Rect(0, 0, w, h)
                else
                    Rect(0, 0, w, (h * 0.42f).toInt())
                builder.setSourceRectHint(hint)
            }

            // FIX: setSeamlessResizeEnabled(false) on Android 12+.
            // Seamless resize was causing the PiP window to flash/flicker
            // and sometimes collapse when orientation changed while in PiP.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setSeamlessResizeEnabled(false)
            }

            enterPictureInPictureMode(builder.build())
            true
        } catch (e: Exception) {
            false
        }
    }
}