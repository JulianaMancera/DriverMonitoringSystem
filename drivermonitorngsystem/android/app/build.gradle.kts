plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.smartalertdrive"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    aaptOptions {
        noCompress += listOf("tflite")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.smartalertdrive"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
dependencies {
    implementation("org.tensorflow:tensorflow-lite-select-tf-ops:2.16.1") {
        exclude(group = "org.tensorflow", module = "tensorflow-lite")
        exclude(group = "com.google.ai.edge.litert", module = "litert")
    }
}

flutter {
    source = "../.."
}