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

    packaging {
        resources {
            // Jetty ships signatures and a module-info that dexing rejects.
            excludes += setOf(
                "META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA",
                "module-info.class", "META-INF/versions/**/module-info.class",
                "about.html", "META-INF/LICENSE*", "META-INF/NOTICE*",
            )
        }
    }

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

    // jUPnP 3.0.3 (Jan 2025) -- the maintained Cling fork. Writing a UPnP
    // *device* means SSDP, SOAP, GENA eventing and DIDL-Lite; pub.dev's
    // packages are all control-point side, so this is the device half.
    // org.jupnp.android pulls com.google.android:android, the ancient stub
    // android.jar, which must be excluded or it collides with the real SDK.
    val jupnp = "3.0.3"
    implementation("org.jupnp:org.jupnp:$jupnp") {
        exclude(group = "com.google.android", module = "android")
    }
    implementation("org.jupnp:org.jupnp.android:$jupnp") {
        exclude(group = "com.google.android", module = "android")
    }
    implementation("org.jupnp:org.jupnp.support:$jupnp") {
        exclude(group = "com.google.android", module = "android")
    }
    // jUPnP's Android configuration serves its HTTP endpoints (device
    // description, SOAP control, GENA subscriptions) through a servlet
    // container, and Jetty is the only one it implements. jUPnP 3.0.3 targets
    // Jetty 9.4 with javax.servlet 3.1 -- the pre-Jakarta generation, which is
    // what makes this dexable for Android at all.
    val jetty = "9.4.53.v20231009"
    implementation("org.eclipse.jetty:jetty-server:$jetty")
    implementation("org.eclipse.jetty:jetty-servlet:$jetty")
    implementation("org.eclipse.jetty:jetty-client:$jetty")
    implementation("javax.servlet:javax.servlet-api:3.1.0")

    // jUPnP logs through slf4j; slf4j-simple writes to stderr, which Android
    // routes to logcat.
    implementation("org.slf4j:slf4j-simple:2.0.16")
    // USB permission is an async user dialog; the probe does blocking control
    // transfers. Both need to be off the UI thread.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // NotificationCompat / ServiceCompat: foreground-service and notification
    // rules changed repeatedly between API 26 and 34.
    implementation("androidx.core:core-ktx:1.15.0")
}

flutter {
    source = "../.."
}
