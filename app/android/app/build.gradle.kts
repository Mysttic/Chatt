import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Dane do podpisania buildu release. Plik z hasłami i sam keystore leżą poza
// gitem (patrz android/.gitignore i docs/building.md). Gdy ich nie ma
// (na przykład w świeżym klonie albo w sesji chmurowej), build release nadal
// przechodzi, tylko podpisany kluczem debug.
val kluczeReleaseFile = rootProject.file("key.properties")
val kluczeRelease = Properties().apply {
    if (kluczeReleaseFile.exists()) {
        FileInputStream(kluczeReleaseFile).use { load(it) }
    }
}
val mamyKluczRelease = kluczeRelease.getProperty("storeFile")?.let { file(it).exists() } == true

android {
    namespace = "com.mysttic.chatt"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mysttic.chatt"
        // Narzędzia pomiarowe z tool/ instalują się obok prawdziwego Chatta,
        // pod osobnym identyfikatorem, i nie ruszają jego danych:
        //   flutter run -t tool/nat_spike.dart -P chattAppIdSuffix=.natspike
        providers.gradleProperty("chattAppIdSuffix").orNull?.let { applicationIdSuffix = it }
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

    signingConfigs {
        if (mamyKluczRelease) {
            create("release") {
                storeFile = file(kluczeRelease.getProperty("storeFile"))
                storePassword = kluczeRelease.getProperty("storePassword")
                keyAlias = kluczeRelease.getProperty("keyAlias")
                keyPassword = kluczeRelease.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (mamyKluczRelease) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "Brak android/key.properties albo keystore'a spod storeFile: " +
                        "build release zostanie podpisany kluczem debug i nie nadaje " +
                        "się do rozdawania. Szczegóły w docs/building.md."
                )
                signingConfigs.getByName("debug")
            }
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
