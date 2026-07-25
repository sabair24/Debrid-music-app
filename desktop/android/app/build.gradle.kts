plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.debridmusic.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // The id the Kotlin app already uses. Keeping it means this APK REPLACES that app on the
        // Shield and the phone instead of installing a second icon beside it — which is the whole
        // point: there is meant to be one DebridMusic, not two that disagree.
        applicationId = "com.debridmusic.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // libmpv ships as a native library per architecture, and carrying all four triples the
            // APK for nothing: the Shield and the S26 Ultra are both arm64.
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // Signing with the debug keys, as the Kotlin app's pipeline did — these APKs are
            // installed by hand and never go through Play.
            signingConfig = signingConfigs.getByName("debug")
        }
        debug {
            // A second id, so a development build sits BESIDE the app you actually use instead of
            // replacing it. Until the D-pad layer lands this app cannot be driven with a remote,
            // and overwriting the working one would leave the Shield with nothing usable on it.
            // Only debug: what ships is a release build, under the real id.
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
    }
}

flutter {
    source = "../.."
}
