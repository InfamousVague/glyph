pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // The watch app's screens (wear/, Compose for Wear OS): Kotlin's own Compose compiler, the same version as Kotlin.
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.0" apply false
}

include(":app")

/*
 * THE WATCH APP (wear/; docs/WATCH.md): voice notes from a Wear OS watch, sent to this app on the phone. Only when
 * asked, since `flutter build apk` and `flutter run` assemble every project in the build and would otherwise compile
 * the watch's Compose screens for every phone build:
 *
 *   GHOST_WEAR=1 flutter build apk ...             (tool/cutover-build.sh sets it: the watch APK beside the phone's)
 *   ./gradlew -Pghost.wear=true :wear:assembleDebug
 */
if (System.getenv("GHOST_WEAR") == "1" || providers.gradleProperty("ghost.wear").orNull == "true") include(":wear")
