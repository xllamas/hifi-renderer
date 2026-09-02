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

        ndk {
            // armeabi-v7a is mandatory, not optional: minSdk 26 puts 32-bit-only
            // phones in scope, and those are exactly the "unused old phone" target.
            // x86_64 is for emulator work on the Oboe fallback path only -- the
            // emulator cannot pass through USB audio.
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }

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
}

flutter {
    source = "../.."
}
