import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La chiave per firmare la versione da mandare al Play Store. Sta fuori dal
// repository: android/key.properties dice dov'è e con che password, ed è in
// .gitignore insieme ai file .jks. Senza quel file si firma con la chiave di
// prova, che basta per installare l'APK a mano ma non per lo store.
val chiave = Properties()
val fileChiave = rootProject.file("key.properties")
if (fileChiave.exists()) {
    FileInputStream(fileChiave).use { chiave.load(it) }
}

android {
    namespace = "dev.tcdesign.deviato"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.tcdesign.deviato"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = chiave.getProperty("keyAlias")
            keyPassword = chiave.getProperty("keyPassword")
            storeFile = chiave.getProperty("storeFile")?.let { file(it) }
            storePassword = chiave.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (fileChiave.exists()) "release" else "debug")
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
