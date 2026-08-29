import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (gitignored). CI writes it from
// the ANDROID_KEYSTORE_* secrets; locally you create it by hand next to upload.jks.
// Absent, the release build falls back to debug signing so `flutter run --release`
// still works — the workflow refuses to publish that fallback on production.
val keyPropsFile = rootProject.file("key.properties")
val keyProps = Properties().apply {
    if (keyPropsFile.exists()) {
        keyPropsFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.communal.collector"
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
        applicationId = "com.communal.collector"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keyPropsFile.exists()) {
                storeFile = keyProps.getProperty("storeFile")?.let { rootProject.file(it) }
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Explicit rather than relying on the variant default: a debuggable
            // release APK lets anyone with adb attach and read a collector's
            // queued receipts and session token off the device.
            isDebuggable = false

            signingConfig = if (keyPropsFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
