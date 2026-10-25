plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release credentials come from an untracked Gradle property or environment
// variables. Never fall back to the debug keystore for a distributable build.
val releaseStoreFile = providers.gradleProperty("POLLO_RELEASE_STORE_FILE")
    .orElse(providers.environmentVariable("POLLO_RELEASE_STORE_FILE"))
val releaseStorePassword = providers.gradleProperty("POLLO_RELEASE_STORE_PASSWORD")
    .orElse(providers.environmentVariable("POLLO_RELEASE_STORE_PASSWORD"))
val releaseKeyAlias = providers.gradleProperty("POLLO_RELEASE_KEY_ALIAS")
    .orElse(providers.environmentVariable("POLLO_RELEASE_KEY_ALIAS"))
val releaseKeyPassword = providers.gradleProperty("POLLO_RELEASE_KEY_PASSWORD")
    .orElse(providers.environmentVariable("POLLO_RELEASE_KEY_PASSWORD"))
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { it.isPresent }

android {
    namespace = "com.pollomovil.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.pollomovil.mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.create("polloRelease") {
                    storeFile = file(releaseStoreFile.get())
                    storePassword = releaseStorePassword.get()
                    keyAlias = releaseKeyAlias.get()
                    keyPassword = releaseKeyPassword.get()
                }
            } else {
                // Keep local release artifacts unsigned until a private signing
                // key is configured; never package them with the debug key.
                signingConfig = null
            }
        }
    }
}

flutter {
    source = "../.."
}
