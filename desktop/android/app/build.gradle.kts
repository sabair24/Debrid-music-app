plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release signing key, when this machine has been given one.
//
// Handed in through the environment rather than committed: a signing key is the one secret that
// proves an APK is THIS app, and a repository that publishes its builds publicly is the last place
// to keep it. CI decodes it from a secret into a file for the length of one run.
val keystorePath: String? = System.getenv("DEBRIDMUSIC_KEYSTORE")
val hasReleaseKey = !keystorePath.isNullOrBlank() && file(keystorePath).exists()

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
                storeFile = file(keystorePath!!)
                storePassword = System.getenv("DEBRIDMUSIC_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("DEBRIDMUSIC_KEY_ALIAS")
                keyPassword = System.getenv("DEBRIDMUSIC_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // The same key every time, or Android will not call it the same app.
            //
            // This used to sign with the DEBUG key, as the Kotlin app's pipeline did. A debug
            // keystore is generated per machine on first use, and a CI runner is a fresh machine
            // every run — so every build was signed by a different key, and Android refuses an
            // update whose signature does not match the app already installed. That is why a new
            // build could only be installed by uninstalling the old one first, which takes your
            // offline copies and your login with it.
            //
            // Falls back to debug when no key is configured, so a checkout without the secrets
            // still builds. Such a build installs, but it still cannot update a signed one.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.lifecycle("No release keystore — signing with the debug key. This APK cannot update a signed install.")
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
