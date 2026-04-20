# TFLite Flutter — keep interpreter and delegate classes
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.lite.**

# Flutter engine
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# sqflite / SQLite JNI
-keep class com.tekartik.sqflite.** { *; }

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# flutter_foreground_task
-keep class com.pravera.flutter_foreground_task.** { *; }

# audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# camera
-keep class io.flutter.plugins.camera.** { *; }

# General: keep all native method bindings
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes *Annotation*
