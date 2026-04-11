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
                }
                override fun onCancel(arguments: Any?) {
                    pipEventSink = null
                }
            })
    }

    // ── Home button pressed ───────────────────────────────────────────────────
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isRecording) {
            val isLandscape = resources.configuration.orientation ==
                Configuration.ORIENTATION_LANDSCAPE
            enterPipMode(isLandscape)
        }
    }

    // ── Back pressed while recording → enter PiP instead of closing ──────────
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

    // ── PiP state change — fires reliably on every PiP enter/exit ────────────
    // FIX: now sends a typed Map instead of a raw Boolean.
    // The old code sent `pipEventSink?.success(isInPictureInPictureMode)` which
    // is a raw Boolean. The Flutter listener does `if (!mounted || raw is! Map)`
    // so a raw Boolean was silently dropped — Flutter never knew PiP had started,
    // so it kept rendering the full screen layout inside the PiP window.
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        runOnUiThread {
            pipEventSink?.success(
                mapOf("type" to "pip", "value" to isInPictureInPictureMode)
            )
            // Send orientation immediately on PiP entry so Flutter can set up
            // the preview dimensions before the first frame renders.
            if (isInPictureInPictureMode) {
                val ori = if (newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE)
                    "landscape" else "portrait"
                pipEventSink?.success(
                    mapOf("type" to "orientation", "value" to ori)
                )
            }
        }
    }

    // ── Device rotates while already in PiP ───────────────────────────────────
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            isInPictureInPictureMode && isRecording) {
            try {
                val isLandscape = newConfig.orientation ==
                    Configuration.ORIENTATION_LANDSCAPE
                val ratio = if (isLandscape) Rational(16, 9) else Rational(9, 16)
                setPictureInPictureParams(
                    PictureInPictureParams.Builder().setAspectRatio(ratio).build()
                )
                // FIX: typed Map — was previously raw String "orientation:landscape"
                // which Flutter's listener (expecting a Map) also silently dropped.
                runOnUiThread {
                    pipEventSink?.success(
                        mapOf(
                            "type"  to "orientation",
                            "value" to if (isLandscape) "landscape" else "portrait"
                        )
                    )
                }
            } catch (_: Exception) { }
        }
    }

    // ── Enter PiP ─────────────────────────────────────────────────────────────
    // FIX: added setSourceRectHint (Android 12+) so the OS zooms only the
    // camera card area into the PiP window, not the entire Flutter screen.
    // Portrait  → top ~42% of screen height, full width (camera card region)
    // Landscape → full screen (camera fills the whole landscape layout)
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
            }

            enterPictureInPictureMode(builder.build())
            true
        } catch (e: Exception) {
            false
        }
    }
}   