package com.example.smartalertdrive

import android.app.PictureInPictureParams
import android.content.Intent
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

    private var isRecording  = false
    private var isInPip      = false

    // FIX B: isStopping prevents onUserLeaveHint from re-entering PiP
    // in the window between the notification stop tap and the moment Flutter
    // confirms isRecording=false via the setRecording channel call.
    // Without this flag, tapping stop in the notification on some devices
    // triggers: stop → home gesture detected → PiP re-entered → stuck again.
    private var isStopping   = false

    private var pipEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "setRecording" -> {
                        isRecording = call.argument<Boolean>("isRecording") ?: false
                        // Clear isStopping once Flutter confirms recording has stopped.
                        // This re-arms the PiP trigger for the next session.
                        if (!isRecording) isStopping = false
                        result.success(null)
                    }

                    "setStopping" -> {
                        isStopping = true
                        result.success(null)
                    }

                    "enterPip" -> {
                        val isLandscape = call.argument<Boolean>("isLandscape") ?: false
                        val success = enterPipMode(isLandscape)
                        result.success(success)
                    }

                    "stopInPip" -> {
                        isStopping  = true
                        isRecording = false
                        // Use applicationContext + the launcher intent to bring the app
                        // to the foreground. On MIUI/HyperOS, calling this.startActivity()
                        // from within the PIP activity (even with REORDER_TO_FRONT) does
                        // not expand the floating window — MIUI appears to suppress it.
                        // applicationContext.startActivity() with the same intent the home
                        // screen launcher uses bypasses this restriction: MIUI treats it as
                        // a genuine "open app" request and expands/closes the PIP window.
                        try {
                            val launchIntent = packageManager
                                .getLaunchIntentForPackage(packageName)
                                ?: Intent(applicationContext, MainActivity::class.java)
                                    .apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
                            applicationContext.startActivity(launchIntent)
                        } catch (_: Exception) { }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    pipEventSink = sink
                    // Send current PiP state immediately when Flutter (re)connects.
                    // This handles the case where pip_service.dart cached stream
                    // reconnects after a hot reload or widget rebuild.
                    sink?.success(mapOf("type" to "pip", "value" to isInPip))
                }
                override fun onCancel(arguments: Any?) {
                    pipEventSink = null
                }
            })
    }

    // FIX B: guard with isStopping so a race between the notification stop
    // and a home-button gesture doesn't re-enter PiP with a dead session.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isRecording && !isInPip && !isStopping) {
            val isLandscape = resources.configuration.orientation ==
                Configuration.ORIENTATION_LANDSCAPE
            enterPipMode(isLandscape)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (isInPip) {
            super.onBackPressed()
            return
        }
        if (isRecording && !isStopping &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val isLandscape = resources.configuration.orientation ==
                Configuration.ORIENTATION_LANDSCAPE
            val entered = enterPipMode(isLandscape)
            if (entered) return
        }
        super.onBackPressed()
    }

    // FIX C: removed the runOnUiThread wrapper.
    //
    // onPictureInPictureModeChanged is already called on the main/UI thread
    // by the Android framework. Wrapping with runOnUiThread posted the event
    // to the end of the message queue — after the activity's resumed() event
    // had already fired on fast devices (Pixel, stock Android).
    //
    // Consequence of the old code on Pixel/stock Android:
    //   resumed() → Flutter clears isInPipProvider=false
    //   [runOnUiThread post fires AFTER resumed]
    //   onPictureInPictureModeChanged(false) → pipEventSink sends pip=false
    //   → pip_service stream emits pip=false AGAIN after monitor_screen already
    //     cleared it — no harm, but adds unnecessary rebuilds.
    //   onPictureInPictureModeChanged(true) on PiP entry → same delay caused
    //   the pip=true event to arrive AFTER resumed on some devices, making
    //   the pip flag briefly flicker false→true→false.
    //
    // Fix: send synchronously on the current (main) thread. Events now arrive
    // in the correct order relative to lifecycle callbacks.
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        isInPip = isInPictureInPictureMode

        // Send synchronously — no runOnUiThread wrapper needed or wanted
        pipEventSink?.success(
            mapOf("type" to "pip", "value" to isInPictureInPictureMode)
        )
        val ori = if (newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE)
            "landscape" else "portrait"
        pipEventSink?.success(
            mapOf("type" to "orientation", "value" to ori)
        )
    }

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