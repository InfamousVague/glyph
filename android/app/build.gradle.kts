plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/*
 * THE PHONE ASSISTANT AND THE SIDE KEY (docs/STAGES_5_6_8_9.md, 8F) are in the app and ON, as they are in Ghost.md's
 * own `main` (docs/PARITY.md, Differs 1): its manifest declares the three services, ASSIST, the capture action and the
 * launcher's "Record note" with no switch at all. (The developer flag this file once cited lives on a branch of
 * ../glyph that was never merged, `voice/assistant-flag`.) So `@bool/ghost_assistant` is true: the three services
 * (GlyphInteractionService, GlyphSessionService, GlyphRecognitionService) and the activity's capture doors are
 * enabled in the manifest, the launcher's shortcut appears, and MeetingBridge.kt honours a capture launch.
 *
 * Installing changes nothing about which app the phone's assistant IS. The app is only offered: Settings > Apps >
 * Default apps > Digital assistant app lists it beside the others, and until a person picks it there (and, on a
 * Samsung, Settings > Advanced features > Side button > Long press > Digital assistant) the side key does what it
 * did.
 *
 * To build WITHOUT them (the app is then not offered as an assistant, has no shortcut, and nothing outside it can
 * start a capture):
 *
 *   GHOST_ASSISTANT=0 flutter build apk ...        (or: --android-project-arg=ghost.assistant=false)
 *
 * Read at configuration time, like the Tauri app's channel switch.
 */
val ghostAssistant = System.getenv("GHOST_ASSISTANT") != "0" && (project.findProperty("ghost.assistant") as String?) != "false"

/*
 * A BUILD MADE TO BE MEASURED (tool/perf.sh android, lib/perf/) fills its library with hundreds of made-up notes and
 * walks itself, so it is never the app a person keeps their notes in: built with GHOST_PERF_ID=1 it is an app of its
 * own beside the others, id and data (com.mattssoftware.glyph.flutter.perf, "Ghost Perf"), and lib/perf/perf_seed.dart
 * fills no library but that one's.
 */
val ghostPerfId = !System.getenv("GHOST_PERF_ID").isNullOrEmpty() && System.getenv("GHOST_PERF_ID") != "0"

android {
    namespace = "com.mattssoftware.ghost_md"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Beside the real app (com.mattssoftware.glyph), never over it: its own id, its own data.
        applicationId = "com.mattssoftware.glyph.flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Never a build made to be measured: an app that fills its library and walks itself is not one to offer as
        // the phone's assistant, and the launcher's shortcut names the real app's id.
        resValue("bool", "ghost_assistant", (ghostAssistant && !ghostPerfId).toString())
        // The icon's "Record note" goes with it, by which file the manifest names: a shortcut's `enabled` has to be
        // the word itself (res/xml/ghost_shortcuts.xml says why).
        manifestPlaceholders["ghostShortcuts"] = if (ghostAssistant && !ghostPerfId) "@xml/ghost_shortcuts" else "@xml/ghost_no_shortcuts"
        if (ghostPerfId) applicationIdSuffix = ".perf"
        manifestPlaceholders["ghostLabel"] = if (ghostPerfId) "Ghost Perf" else "Ghost Flutter"
    }

    buildFeatures {
        // For `resValue` above, which is off unless asked from AGP 9.
        resValues = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Nothing is shrunk or renamed: the core calls Kotlin by name over JNI (MeetingService and friends),
            // and R8 took WorkManager's database with it, so a release build died before its first frame.
            isMinifyEnabled = false
            isShrinkResources = false
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
    // A meeting's write-up with the app closed (recordings/RecordingWorker.kt): the Tauri app's own line and
    // version, ../glyph/src-tauri/gen/android/app/build.gradle.kts. A plain Worker, so no coroutines artifact.
    implementation("androidx.work:work-runtime:2.9.1")
    // Whether the app is in front when a write-up ends (recordings/WriteUp.kt, ProcessLifecycleOwner): the Tauri
    // app's own line and version.
    implementation("androidx.lifecycle:lifecycle-process:2.10.0")
    // The ported classes' own tests (app/src/test): SoundMix, WavSpool, the notification's counter and line.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
