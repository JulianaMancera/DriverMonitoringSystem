package com.example.smartalertdrive

 
import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
 
class MainActivity : FlutterActivity() {
 
    private val CHANNEL = "com.bantaydrive/pip"
    private var isRecording = false
 
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
 
        // Method channel so Flutter can tell native when recording starts/stops
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setRecording" -> {
                        isRecording = call.argument<Boolean>("isRecording") ?: false
                        result.success(null)
                    }
                    "enterPip" -> {
                        val success = enterPipMode()
                        result.success(success)
                    }
                    else -> result.notImplemented()
                }
            }
    }
 
    // Called when user presses the HOME button — this is the key hook
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isRecording) {
            enterPipMode()
        }
    }
 
    // Called when PiP mode changes (entering or exiting)
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Notify Flutter about PiP state change
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL)
                .invokeMethod("onPipChanged", mapOf("isInPip" to isInPictureInPictureMode))
        }
    }
 
    private fun enterPipMode(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16)) // portrait — matches camera preview
                .build()
            enterPictureInPictureMode(params)
            true
        } catch (e: Exception) {
            false
        }
    }
}
 