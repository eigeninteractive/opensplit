import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Local upload key comes from gitignored android/key.properties. CI passes
// credentials through the environment so passwords never need serialization.
//
// Absent on a fresh clone and in CI, and that is a supported state: the release
// build then falls back to the debug key below, so `flutter build apk --debug`
// and a contributor's first checkout both keep working. What must never happen
// is a *shipped* build silently taking that fallback, so the release block
// fails loudly instead — see the check in signingConfigs.
//
// See android/key.properties.example.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val ciSigning = mapOf(
    "storeFile" to "ANDROID_UPLOAD_KEYSTORE_PATH",
    "storePassword" to "ANDROID_UPLOAD_STORE_PASSWORD",
    "keyAlias" to "ANDROID_UPLOAD_KEY_ALIAS",
    "keyPassword" to "ANDROID_UPLOAD_KEY_PASSWORD"
)
if (ciSigning.values.any { System.getenv(it) != null }) {
    ciSigning.forEach { (property, variable) ->
        val value = System.getenv(variable)
        require(!value.isNullOrEmpty()) { "Missing signing variable: $variable" }
        keystoreProperties.setProperty(property, value)
    }
}
val hasUploadKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.eigeninteractive.opensplit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications schedules against java.time, which is
        // only available natively on newer Android. Desugaring backports it;
        // without this the build fails at checkDebugAarMetadata.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.eigeninteractive.opensplit"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // The debug key is a fallback for local release builds and for CI,
            // never for anything that leaves this machine: Play rejects a
            // bundle signed with it outright, and App Links would verify
            // against a certificate no real install carries.
            //
            // Play App Signing means the upload key is not the key users end up
            // trusting — Play re-signs with the app signing key — so
            // assetlinks.json has to list BOTH fingerprints. See
            // site/.well-known/README.md.
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// A release AAB is the artefact that goes to Play, and signing it with the
// debug key is the mistake that is invisible until the upload is rejected —
// or, worse, until App Links quietly stop verifying for every real user.
//
// APKs are deliberately exempt: `flutter build apk --release` is how the app
// gets onto a device for testing, and CI builds one on every push.
tasks.matching { it.name.startsWith("bundle") && it.name.contains("Release") }
    .configureEach {
        doFirst {
            if (!hasUploadKey) {
                throw GradleException(
                    "Refusing to build a release bundle with the debug key. " +
                        "Create android/key.properties from " +
                        "android/key.properties.example and point it at the " +
                        "upload keystore."
                )
            }
        }
    }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
