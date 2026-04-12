plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.smartalertdrive"
    compileSdk = flutter.compileSdkVersion
    // FIX: Pin NDK version explicitly — flutter.ndkVersion can resolve to an
    // incompatible version depending on the Flutter channel. 27.0.12077973 is
    // the version bundled with Flutter 3.16–3.24 stable and supports JDK 17.
    ndkVersion = "27.0.12077973"

    compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
    }
    
    kotlinOptions {
        jvmTarget = "21"
    }

    defaultConfig {
        applicationId = "com.example.smartalertdrive"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            isDebuggable = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core desugaring — required for flutter_foreground_task + java.time APIs
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Required by flutter_foreground_task for background camera service
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.2.0")

    // Required for multidex support (minSdk < 21 not needed here, but safe to keep)
    implementation("androidx.multidex:multidex:2.0.1")
}