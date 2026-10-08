plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/*
 * THE PHONE ASSISTANT AND THE SIDE KEY (docs/STAGES_5_6_8_9.md, 8F) are in the app and OFF: the web app keeps the
 * phone assistant behind a developer flag, and here the flag is the build's. To turn it on, build with
 *
 *   GHOST_ASSISTANT=1 flutter build apk --debug ...          (or: flutter build apk ... -Pghost.assistant=true
 *                                                             through --android-project-arg=ghost.assistant=true)
 *
 * which makes `@bool/ghost_assistant` true: the three services (GlyphInteractionService, GlyphSessionService,
 * GlyphRecognitionService) and the activity's capture doors are then enabled in the manifest, the launcher's
 * "Record note" shortcut appears, and MeetingBridge.kt honours a capture launch. Then, on the phone: Settings >
 * Apps > Default apps > Digital assistant app > Ghost Flutter, and on a Samsung, Settings > Advanced features >
 * Side button > Long press > Digital assistant. Read at configuration time, like the Tauri app's channel switch.
 */
val ghostAssistant = !System.getenv("GHOST_ASSISTANT").isNullOrEmpty() && System.getenv("GHOST_ASSISTANT") != "0" ||
    (project.findProperty("ghost.assistant") as String?) == "true"

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
        resValue("bool", "ghost_assistant", ghostAssistant.toString())
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
