import java.io.FileInputStream
import java.util.Properties

// The upload key for Google Play lives outside the repo (#343): android/key.properties
// (git ignores it) names the keystore and its passwords. Without it the release build
// is signed with the debug key: it still installs, but Play refuses it.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasUploadKey = keystorePropertiesFile.exists()
if (hasUploadKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.officialnews.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        resValues = true // Firebase's values below
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.officialnews.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Firebase's Android values (#343), for Analytics' native side, which reads them from
        // resources, not from the Dart options: key.properties names the same JSON file that
        // the build passes with --dart-define-from-file (kept outside the repo). Without it,
        // the build has no Firebase on Android, as before.
        (keystoreProperties["firebaseDefines"] as String?)?.let { path ->
            @Suppress("UNCHECKED_CAST")
            val firebase = groovy.json.JsonSlurper().parse(file(path)) as Map<String, String>
            resValue("string", "google_app_id", firebase.getValue("FIREBASE_APP_ID"))
            resValue("string", "google_api_key", firebase.getValue("FIREBASE_API_KEY"))
            resValue("string", "gcm_defaultSenderId", firebase.getValue("FIREBASE_SENDER_ID"))
            resValue("string", "project_id", firebase.getValue("FIREBASE_PROJECT_ID"))
        }
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
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
