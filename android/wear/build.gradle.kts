import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

/*
 * GHOST.MD ON THE WRIST (docs/WATCH.md): a Wear OS app that records a voice note at a tap and hands it to the phone's
 * Ghost.md over the Wearable Data Layer, where it becomes a voice note as if it had been recorded there.
 *
 * THE SAME APP TO GOOGLE PLAY SERVICES. The Data Layer only lets two apps talk when they have the same application id
 * AND are signed with the same certificate, so this module follows the phone's own switches
 * (app/build.gradle.kts): the id is `com.mattssoftware.glyph` in the build that replaces the Tauri app
 * (GHOST_CUTOVER=1), which is the Ghost.md on Matt's phone, `com.mattssoftware.glyph.flutter` otherwise, and `.perf`
 * after it in a build made to be measured; a release is signed from the very file the phone's release is signed
 * from (~/.config/glyph/android-signing.properties, or $GLYPH_ANDROID_SIGNING), and a debug build with this
 * machine's debug key, as the phone's debug build is. A debug watch app therefore pairs with a debug phone app from
 * the same machine, and a release with a release, never one with the other.
 *
 * Wear OS 3 and later (API 30): Samsung's Galaxy Watch4 and every Galaxy Watch since, and TAG Heuer's Calibre E4,
 * which shipped with Wear OS 3. The microphone opens only on a tap (the screen's button, the tile, the complication or
 * the shortcut): no always-on microphone, ever.
 */
val ghostCutover = (!System.getenv("GHOST_CUTOVER").isNullOrEmpty() && System.getenv("GHOST_CUTOVER") != "0") || (project.findProperty("ghost.cutover") as String?) == "true"
val ghostPerfId = !System.getenv("GHOST_PERF_ID").isNullOrEmpty() && System.getenv("GHOST_PERF_ID") != "0"

/*
 * The version the Flutter tool wrote for the phone's build (local.properties `flutter.versionName`, from pubspec.yaml or
 * --build-name), so the two APKs of one build say the same version. The code: the Tauri app's numbering in the
 * cutover build, as the phone's is (1.15.0 is 1015000), else Flutter's. The Data Layer does not compare them.
 */
val flutterProps = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val wearVersionName = flutterProps.getProperty("flutter.versionName") ?: "1.0.0"
fun cutoverCode(name: String): Int {
    val parts = name.substringBefore('-').substringBefore('+').split('.').map { it.toIntOrNull() ?: 0 }
    return if (parts.size == 3) parts[0] * 1_000_000 + parts[1] * 1_000 + parts[2] else 1
}
val wearVersionCode = if (ghostCutover) cutoverCode(wearVersionName) else (flutterProps.getProperty("flutter.versionCode")?.toIntOrNull() ?: 1)

val releaseSigning = Properties().apply {
    val path = System.getenv("GLYPH_ANDROID_SIGNING") ?: "${System.getProperty("user.home")}/.config/glyph/android-signing.properties"
    val propFile = File(path)
    if (propFile.exists()) propFile.inputStream().use { load(it) }
}

android {
    namespace = "com.mattssoftware.ghost_md.wear"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = if (ghostCutover) "com.mattssoftware.glyph" else "com.mattssoftware.glyph.flutter"
        if (ghostPerfId) applicationIdSuffix = ".perf"
        minSdk = 30
        targetSdk = 36
        versionCode = wearVersionCode
        versionName = wearVersionName
        manifestPlaceholders["ghostLabel"] = if (ghostPerfId) "Ghost Perf" else if (ghostCutover) "Ghost.md" else "Ghost Markdown"
    }

    sourceSets {
        // The words both ends of the link speak (wear-shared/: the paths, the capability names, a take's frame),
        // compiled into the phone's app too, so neither can drift from the other.
        getByName("main").java.srcDir("../wear-shared/kotlin")
    }

    buildFeatures {
        compose = true
    }

    signingConfigs {
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
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            // Shrunk, unlike the phone's (whose core calls Kotlin by name over JNI): a watch's storage is small and
            // Compose unshrunk is most of 30 MB. Nothing here is reached by name but what the manifest names (the
            // activity, the services), which R8 keeps by itself.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.05.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.activity:activity-compose:1.12.4")
    // Compose for Wear OS: the round list, the time along the edge, the scroll indicator.
    implementation("androidx.wear.compose:compose-foundation:1.5.6")
    implementation("androidx.wear.compose:compose-material:1.5.6")
    // The recording's chip on the watch face and in the app launcher's recents while it records.
    implementation("androidx.wear:wear-ongoing:1.1.0")
    implementation("androidx.core:core-ktx:1.17.0")
    // The tile ("Record a note") and the complication.
    implementation("androidx.wear.tiles:tiles:1.5.0")
    implementation("androidx.wear.protolayout:protolayout:1.3.0")
    implementation("androidx.wear.protolayout:protolayout-material:1.3.0")
    implementation("androidx.wear.watchface:watchface-complications-data-source-ktx:1.2.1")
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
    // Sending a take to the phone, and trying again later when it is not near.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
