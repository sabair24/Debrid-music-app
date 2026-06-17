plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

// Pin the entire Compose stack to one consistent train. A transitive constraint
// was dragging androidx.compose.foundation/ui up to the current 1.10.x while the
// pinned material-ripple (1.6.8) / material3 (1.2.1) stayed behind. Foundation
// 1.10's clickable requires the new ripple (IndicationNodeFactory) and crashes on
// the old PlatformRipple, so ANY clickable (e.g. the mini-player) crashed the app.
configurations.all {
    resolutionStrategy.eachDependency {
        when {
            requested.group == "androidx.compose.material3" -> useVersion("1.3.1")
            requested.group.startsWith("androidx.compose") &&
                requested.group != "androidx.compose" -> useVersion("1.7.6")
        }
    }
}

android {
    namespace = "com.debridmusic.app"
    compileSdk = 35

    // CI passes the GitHub Actions run number as BUILD_NUMBER. Locally it
    // defaults to 0 so a dev build always sees the published release as newer.
    val ciBuildNumber = System.getenv("BUILD_NUMBER")?.toIntOrNull() ?: 0

    defaultConfig {
        applicationId = "com.debridmusic.app"
        minSdk = 26
        targetSdk = 35
        versionCode = ciBuildNumber.coerceAtLeast(1)
        versionName = "1.0.0"

        // Used by the in-app updater to compare against the latest GitHub release.
        // Points at the PUBLIC releases repo (source stays private), so the
        // unauthenticated update check and APK download work on-device.
        buildConfigField("int", "BUILD_NUMBER", "$ciBuildNumber")
        buildConfigField("String", "GITHUB_REPO", "\"sabair24/Debrid-music-app-releases\"")

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }
    }

    // Stable signing key committed to this (private) repo so every CI build is
    // signed identically. Without this each build got a fresh debug key, so
    // updates failed with a signature mismatch and required an uninstall — which
    // also broke the in-app updater. App-signing key only; the source repo is private.
    signingConfigs {
        create("stable") {
            storeFile = file("debridmusic.keystore")
            storePassword = "debridmusic"
            keyAlias = "debridmusic"
            keyPassword = "debridmusic"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("stable")
        }
        release {
            isMinifyEnabled = true
            signingConfig = signingConfigs.getByName("stable")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    buildFeatures { compose = true; buildConfig = true }

    packaging {
        resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" }
    }
}

dependencies {
    // Core
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)

    // Compose
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    debugImplementation(libs.androidx.ui.tooling)

    // Hilt
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.hilt.navigation.compose)

    // Room
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)

    // Media3 / ExoPlayer
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.session)
    implementation(libs.media3.ui)
    implementation(libs.media3.datasource.okhttp)

    // Networking
    implementation(libs.retrofit)
    implementation(libs.retrofit.gson)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)

    // Image loading
    implementation(libs.coil.compose)

    // Serialization
    implementation(libs.gson)

    // Coroutines
    implementation(libs.kotlinx.coroutines.android)

    // TV
    implementation(libs.androidx.tv.foundation)
    implementation(libs.androidx.tv.material)

    // Preferences
    implementation(libs.androidx.datastore.preferences)

    // Palette — dynamic accent colours from artwork (Roon-style theming)
    implementation(libs.androidx.palette)

    // SAF — user-chosen download location (incl. SD card)
    implementation(libs.androidx.documentfile)

    // Tidal official SDK (now on Kotlin 2.2). Auth first; player added after auth builds.
    implementation(libs.tidal.auth)
}
