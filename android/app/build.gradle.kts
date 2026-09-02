plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hifirend"
    compileSdk = 36
    // Pinned rather than inherited from Flutter: the native engine must build
    // against a known NDK, and a silent NDK bump would change libusb behaviour.
    ndkVersion = "28.2.13676358"

    buildFeatures {
        // Oboe ships as a prefab AAR; the fallback sink links against it.
        prefab = true
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.hifirend"
        // 26 (Android 8.0): nothing in the feature set needs more, and this is where
        // NotificationChannel and AAudio become uniform. See doc/implementation-plan.md.
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Deliberately NO ndk.abiFilters here.
        //
        // Flutter's Gradle plugin already derives the ABI set from
        // --target-platform, defaulting to exactly what we want:
        // arm64-v8a, armeabi-v7a (32-bit phones are in the target population)
        // and x86_64 (emulator, Oboe fallback path only -- an emulator cannot
        // pass through USB audio). Setting ndk.abiFilters here is not just
        // redundant, it is a hard conflict: it makes `flutter build apk
        // --split-per-abi` fail with "Conflicting configuration ... in ndk
        // abiFilters cannot be present when splits abi filters are set".
        //
        // To build a single-ABI APK, use Flutter's own mechanism:
        //   flutter build apk --debug --target-platform android-arm
        //   flutter build apk --release --split-per-abi

        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=c++_shared")
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation("com.google.oboe:oboe:1.9.3")
    // USB permission is an async user dialog; the probe does blocking control
    // transfers. Both need to be off the UI thread.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}

flutter {
    source = "../.."
}
