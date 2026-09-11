import java.util.Properties

// Release signing credentials, which are deliberately not in the repository.
//
// android/key.properties names the keystore and holds its passwords; it is
// gitignored, as are *.jks and *.keystore. Nothing here carries a default,
// because every possible default is wrong: a missing keystore must not
// silently produce a debug-signed APK that looks like a release.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) keystorePropertiesFile.inputStream().use { load(it) }
}

// A half-filled key.properties is worse than an absent one: it fails deep
// inside AGP with a message about a null path, several minutes into a build.
// Check it here, where the error can name the file and the missing key.
if (hasReleaseKeystore) {
    val missing = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    require(missing.isEmpty()) {
        "android/key.properties is missing: ${missing.joinToString(", ")}"
    }
    val store = file(keystoreProperties.getProperty("storeFile"))
    require(store.exists()) {
        "android/key.properties points storeFile at ${store.path}, which does not exist"
    }
}

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
        // The identity Play knows the app by, and deliberately not the same
        // as the namespace above.
        //
        // The Kotlin package stays com.hifirend because 23 JNI entry points
        // are named for it -- Java_com_hifirend_NativeBridge_* is derived from
        // the class's package, so renaming it silently unbinds every native
        // call -- and proguard-rules.pro keeps classes by that name too.
        // applicationId and namespace are independent by design; only this one
        // has to match the Play Console listing.
        applicationId = "com.acelery.hifirend"
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

    signingConfigs {
        // Created only when the credentials are present, so a clone without
        // the keystore still configures and can build a debug APK.
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    testOptions {
        unitTests {
            // OpenHomeTrackList logs, and android.util.Log is a stub in a JVM
            // unit test. Returning defaults rather than throwing is what lets
            // the playlist model -- ids, ordering, the IdArray encoding -- be
            // tested off-device, which is where it needs testing: a wrong byte
            // order is invisible until a real controller decodes it.
            isReturnDefaultValues = true
        }
    }

    buildTypes {
        release {
            // Signed with the upload key from android/key.properties. Without
            // it the build still runs -- `flutter run --release` has to work
            // for anyone who has cloned this -- but it is debug-signed, which
            // Play rejects, so it says so rather than letting the artefact
            // reach an upload form before anyone finds out.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "hifirend: android/key.properties not found. The release build " +
                    "will be signed with the DEBUG key and cannot be uploaded to Play."
                )
                signingConfigs.getByName("debug")
            }

            // R8 needs telling what not to touch. Everything this app does
            // across a boundary -- jUPnP's annotated actions, the JNI bridge --
            // is resolved by name at runtime and looks unused to a shrinker.
            // See proguard-rules.pro; the failure mode is a build that works
            // and an app that does not.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")

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
