import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/*
 * THE PHONE ASSISTANT AND THE SIDE KEY (docs/STAGES_5_6_8_9.md, 8F) are in the app and OFF (Matt, 2026-10-11: "off by
 * default behind a developer flag"; docs/PARITY.md, Differs 1). `@bool/ghost_assistant` is false: the three services
 * (GlyphInteractionService, GlyphSessionService, GlyphRecognitionService) and the activity's capture doors are in the
 * manifest but disabled, the launcher has no "Record note", and MeetingBridge.kt reads no launch as a capture. So
 * the app is not offered as a digital assistant and nothing outside it can start a recording.
 *
 * Two things turn them on:
 *
 * - a developer, for one phone: Settings > Developer > Work in progress > Voice assistant (lib/core/wip.dart,
 *   AssistantSwitch.kt), the switch Ghost.md's unmerged branch `voice/assistant-flag` describes (its DESIGN §146);
 * - the build, for everyone who installs it:
 *
 *     GHOST_ASSISTANT=1 flutter build apk ...        (or: --android-project-arg=ghost.assistant=true)
 *
 * Either way the app is only OFFERED: Settings > Apps > Default apps > Digital assistant app lists it beside the
 * others, and until a person picks it there (and, on a Samsung, Settings > Advanced features > Side button > Long
 * press > Digital assistant) the side key does what it did. A phone where the Tauri app WAS the assistant loses that
 * with the update that replaces it (the service it named is disabled), and Android goes back to its own.
 *
 * Read at configuration time, like the Tauri app's channel switch.
 */
val ghostAssistant = System.getenv("GHOST_ASSISTANT") == "1" || (project.findProperty("ghost.assistant") as String?) == "true"

/*
 * A BUILD MADE TO BE MEASURED (tool/perf.sh android, lib/perf/) fills its library with hundreds of made-up notes and
 * walks itself, so it is never the app a person keeps their notes in: built with GHOST_PERF_ID=1 it is an app of its
 * own beside the others, id and data (com.mattssoftware.glyph.flutter.perf, "Ghost Perf"), and lib/perf/perf_seed.dart
 * fills no library but that one's.
 */
val ghostPerfId = !System.getenv("GHOST_PERF_ID").isNullOrEmpty() && System.getenv("GHOST_PERF_ID") != "0"

/*
 * THE BUILD THAT REPLACES GHOST.MD'S TAURI APP (docs/CUTOVER.md). Not the default: built with
 *
 *   GHOST_CUTOVER=1 flutter build apk --release --build-name=2.0.0      (or: --android-project-arg=ghost.cutover=true)
 *
 * it is the Tauri app's next version as far as Android can tell, so it installs OVER that app and wakes in its data
 * folder, where lib/carry/tauri_carry.dart brings what the page kept into this app's stores:
 *
 * - the id is `com.mattssoftware.glyph` and the name is "Ghost.md";
 * - the version code is made from the version name the way Tauri made it (major * 1,000,000 + minor * 1,000 +
 *   patch), and the build is refused unless that is above the Tauri app's last, 1.15.0 = 1015000
 *   (tauri/src-tauri/gen/android/app/tauri.properties): Android will not install a lower code over a higher one;
 * - the launcher's activity is still called `com.mattssoftware.glyph.MainActivity` (an alias of this app's own, in
 *   the manifest), since a home screen keeps an icon and a pinned "Record note" by that name and drops both when the
 *   name goes; the shortcut names the same id and class the Tauri app's did (res/xml/ghost_cutover_shortcuts.xml).
 *
 * Everything else the system or another app holds the Tauri app by is the same in every build of this app: the
 * `ghostmd` links, the capture action, the documents provider's authority (`<id>.library`), the services' and the
 * workers' class names, the notification channels' ids and the Kotlin side's preference files.
 *
 * An update is only installed over an app signed with the same certificate, and the Tauri app's is pinned in
 * tauri/src-tauri/apk-signer.sha256. A release build is signed from the file the Tauri app's build reads,
 * outside every repo: ~/.config/glyph/android-signing.properties, or the file $GLYPH_ANDROID_SIGNING names, with
 * `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. Without that file a release build is signed with
 * this machine's debug key, which is only the right certificate on a machine where the two are the same key.
 */
val ghostCutover = (!System.getenv("GHOST_CUTOVER").isNullOrEmpty() && System.getenv("GHOST_CUTOVER") != "0") || (project.findProperty("ghost.cutover") as String?) == "true"
val tauriLastVersionCode = 1015000
if (ghostCutover && ghostPerfId) throw GradleException("GHOST_CUTOVER and GHOST_PERF_ID are two different apps: a measured build never replaces Ghost.md.")

/** A version name as Tauri numbered it: 1.15.0 is 1015000. */
fun tauriVersionCode(name: String): Int {
    val parts = name.substringBefore('-').substringBefore('+').split('.').map { it.toIntOrNull() ?: throw GradleException("GHOST_CUTOVER needs a version name of three numbers (--build-name=2.0.0), not $name.") }
    if (parts.size != 3 || parts[1] > 999 || parts[2] > 999) throw GradleException("GHOST_CUTOVER needs a version name of three numbers (--build-name=2.0.0), not $name.")
    return parts[0] * 1_000_000 + parts[1] * 1_000 + parts[2]
}

val releaseSigning = Properties().apply {
    val path = System.getenv("GLYPH_ANDROID_SIGNING") ?: "${System.getProperty("user.home")}/.config/glyph/android-signing.properties"
    val propFile = File(path)
    if (propFile.exists()) propFile.inputStream().use { load(it) }
}

android {
    namespace = "com.mattssoftware.ghost_md"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Beside the real app (com.mattssoftware.glyph), never over it: its own id, its own data. Unless this is the
        // build that replaces it (`ghostCutover`, above).
        applicationId = if (ghostCutover) "com.mattssoftware.glyph" else "com.mattssoftware.glyph.flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = if (ghostCutover) {
            val code = tauriVersionCode(flutter.versionName)
            if (code <= tauriLastVersionCode) throw GradleException("GHOST_CUTOVER: version ${flutter.versionName} is code $code, which is not above the Tauri app's $tauriLastVersionCode (1.15.0). Android would refuse the update. Build with --build-name=2.0.0 or later.")
            code
        } else {
            flutter.versionCode
        }
        versionName = flutter.versionName
        // Never a build made to be measured: an app that fills its library and walks itself is not one to offer as
        // the phone's assistant, and the launcher's shortcut names the real app's id.
        resValue("bool", "ghost_assistant", (ghostAssistant && !ghostPerfId).toString())
        // The icon's "Record note" goes with it, by which file the manifest names: a shortcut's `enabled` has to be
        // the word itself (res/xml/ghost_shortcuts.xml says why).
        manifestPlaceholders["ghostShortcuts"] = if (!ghostAssistant || ghostPerfId) "@xml/ghost_no_shortcuts" else if (ghostCutover) "@xml/ghost_cutover_shortcuts" else "@xml/ghost_shortcuts"
        if (ghostPerfId) applicationIdSuffix = ".perf"
        manifestPlaceholders["ghostLabel"] = if (ghostPerfId) "Ghost Perf" else if (ghostCutover) "Ghost.md" else "Ghost Flutter"
        // Which of the two is the launcher's: this app's own activity, or (replacing the Tauri app) the alias that
        // carries that app's activity's name. A category nothing asks for is how the other is not one.
        resValue("bool", "ghost_cutover", ghostCutover.toString())
        manifestPlaceholders["ghostOwnLauncher"] = if (ghostCutover) "com.mattssoftware.glyph.category.NOT_THE_LAUNCHER" else "android.intent.category.LAUNCHER"
        manifestPlaceholders["ghostTauriLauncher"] = if (ghostCutover) "android.intent.category.LAUNCHER" else "com.mattssoftware.glyph.category.NOT_THE_LAUNCHER"
    }

    buildFeatures {
        // For `resValue` above, which is off unless asked from AGP 9.
        resValues = true
    }

    signingConfigs {
        // The Tauri app's own key, from its own file (the header above `ghostCutover` says which).
        if (releaseSigning.getProperty("storeFile") != null) {
            create("release") {
                storeFile = File(releaseSigning.getProperty("storeFile"))
                storePassword = releaseSigning.getProperty("storePassword")
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The release key where its file is, and this machine's debug key where it is not, so
            // `flutter run --release` still works on a machine without it.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
    // version, tauri/src-tauri/gen/android/app/build.gradle.kts. A plain Worker, so no coroutines artifact.
    implementation("androidx.work:work-runtime:2.9.1")
    // Whether the app is in front when a write-up ends (recordings/WriteUp.kt, ProcessLifecycleOwner): the Tauri
    // app's own line and version.
    implementation("androidx.lifecycle:lifecycle-process:2.10.0")
    // Documents in notes (Documents.kt): Google's document scanner, its screen delivered by Play services (the app
    // holds no camera), and the words read in pictures and PDFs on the phone, the Latin model inside the app so it
    // reads with no connection and nothing leaves the phone.
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    implementation("com.google.mlkit:text-recognition:16.0.1")
    // The ported classes' own tests (app/src/test): SoundMix, WavSpool, the notification's counter and line.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
