import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release keystore, when the machine building has one.
//
// Kept OUT of the repository, in android/key.properties, because it holds a password. The file is
// read if it is there and ignored if it is not, so a clone with no keystore still builds — it just
// produces a debug-signed APK, which is what every build did until now.
//
// That mattered more than it looked: an APK signed with the debug key cannot be upgraded over one
// signed with a release key, and vice versa. Android refuses the install outright. So the day a real
// key arrives, the app has to be uninstalled once before the first properly signed build will go on.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProps.getProperty("storeFile") != null &&
    rootProject.file(keyProps.getProperty("storeFile")).exists()

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

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // A real key when this machine has one, the debug key otherwise. Falling back rather
            // than failing keeps a fresh clone buildable; the build log says which one was used, so
            // an unsigned-in-earnest APK cannot be mistaken for a signed one.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

// Said out loud at configure time. "Is this APK actually signed?" should not be a question anyone has
// to answer by running apksigner afterwards.
gradle.projectsEvaluated {
    println(
        if (hasReleaseKey) {
            "DebridMusic: release-APK wordt gesigneerd met de sleutel uit android/key.properties"
        } else {
            "DebridMusic: GEEN android/key.properties — release-APK wordt met de DEBUG-sleutel gesigneerd"
        }
    )
}
