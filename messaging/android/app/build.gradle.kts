import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/*
 * THE RELEASE KEY. Android installs an update only over an app signed with the same certificate, so every release is
 * signed with one key kept outside the repository: ~/.config/ghostmessaging/signing.properties (or the file
 * $GHOSTMESSAGING_SIGNING names) with storeFile, storePassword, keyAlias and keyPassword. tool/release.mjs makes it
 * the first time. Without it a release build is signed with this machine's debug key, and tool/release.mjs refuses to
 * publish that.
 */
val signingFile = file(System.getenv("GHOSTMESSAGING_SIGNING") ?: "${System.getProperty("user.home")}/.config/ghostmessaging/signing.properties")
val signing = Properties().apply { if (signingFile.exists()) signingFile.inputStream().use { load(it) } }

android {
    namespace = "com.infamousvague.ghostmessaging"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.infamousvague.ghostmessaging"
        // 26: Notification channels and MessagingStyle without the support library. 29: RoleManager for the SMS role.
        minSdk = 29
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // arm64 only: the phones this is for.
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    signingConfigs {
        if (signing.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The messages live in Android's own SMS database, not the app's, so reinstalling over a differently
            // signed build (a debug-key build from a machine without the release key) loses nothing.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
    testImplementation("junit:junit:4.13.2")
}
