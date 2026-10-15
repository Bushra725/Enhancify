plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.mai.photo.editor.app.picture.face.art.lab"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mai.photo.editor.app.picture.face.art.lab"
        // google_mobile_ads 9.x requires 24; unchanged vs previous Play release.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Phones/tablets are ARM. Skipping x86/x86_64 cuts a large emulator-only
        // native payload from the bundle (OpenCV alone was ~50 MB on x86_64).
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
        // Keep dependency language packs aligned with in-app languages.
        resourceConfigurations += listOf(
            "en", "ur", "ar", "es", "hi", "fr",
            "de", "it", "pt", "ru", "tr", "id", "ms",
            "bn", "pa", "fa", "ps", "zh", "ja", "ko",
            "vi", "th", "ta", "fil", "sw", "nl", "pl", "gu", "mr",
        )
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isDebuggable = false
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            pickFirsts += "**/libc++_shared.so"
            // Compress .so in delivered APKs — smaller Play downloads.
            useLegacyPackaging = true
            excludes += setOf("**/x86/**", "**/x86_64/**")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.19.0"))
    implementation("com.google.firebase:firebase-analytics")
    // OpenCV removed (~19–50 MB per ABI). Object remove + BG fallback use
    // on-device Dart algorithms so photo export quality stays high.
    implementation("androidx.core:core-ktx:1.13.1")
}
