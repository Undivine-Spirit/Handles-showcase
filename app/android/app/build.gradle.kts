plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.undivinespirit.handles_app"
    // Pinned rather than flutter.compileSdkVersion's default (33 as of
    // Flutter 3.47.1) - flutter_displaymode (added for the 120Hz fix)
    // transitively pulls in androidx libraries that require compiling
    // against API 34+. AGP 9.1.0 here supports well past 36; this only
    // changes the compile-time API surface, not targetSdk's runtime
    // behavior opt-ins, so it's a narrow fix for the actual build failure.
    compileSdk = 36
    // Deliberately not set to flutter.ndkVersion (the template default) -
    // none of this app's plugins (battery_plus, flutter_secure_storage,
    // shared_preferences, url_launcher, path_provider,
    // flutter_local_notifications) declare any native/NDK build step
    // (verified: no ndkVersion/externalNativeBuild reference in any of
    // their own android/build.gradle files). Setting this unconditionally
    // makes AGP eagerly resolve that exact NDK revision during project
    // configuration even though nothing uses it - and on this machine
    // that resolution goes through cmdline-tools 23.0's new "android" CLI,
    // which mishandles the classic `ndk;<version>` package-ID syntax
    // Flutter's Gradle plugin passes it (splits on the `;` and looks up
    // "ndk" and the version number as two separate, nonexistent packages).
    // Leaving it unset lets AGP skip that resolution entirely; revisit if
    // a future plugin actually needs native compilation.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (its own README says so,
        // and `checkDebugAarMetadata` fails without it) - it uses java.time
        // APIs for scheduled notifications that need desugaring to work
        // back to this app's minSdk.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.undivinespirit.handles_app"
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
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
    // Version checked against Google's real Maven metadata
    // (dl.google.com/dl/android/maven2/.../desugar_jdk_libs/maven-metadata.xml)
    // at the time this was added, not copied from a possibly-stale example.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
