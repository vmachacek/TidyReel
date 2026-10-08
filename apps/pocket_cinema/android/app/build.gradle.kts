import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Personal APKs keep the existing development signature so installing an update
// does not erase the tablet's library. Store releases use a separate upload key.
// Flutter's Windows process environment uppercases names, including the Gradle
// property suffix. Keep this opt-in property uppercase throughout the toolchain.
val personalInstall = providers.gradleProperty("POCKET_CINEMA_PERSONAL_INSTALL").orNull == "true"
if (personalInstall && (gradle.startParameter.taskNames.isEmpty() ||
        gradle.startParameter.taskNames.any { it.substringAfterLast(':') != "assembleRelease" })) {
    throw GradleException("Personal signing is only allowed for assembleRelease APKs. Use tool/build-play-bundle.ps1 for Google Play.")
}
val uploadProperties = Properties()
val uploadPropertiesFile = rootProject.file("key.properties")
if (!personalInstall && uploadPropertiesFile.exists()) {
    uploadPropertiesFile.inputStream().use { uploadProperties.load(it) }
}
val validateUploadSigning = tasks.register("validateUploadSigning") {
    doLast {
        if (!personalInstall) {
            if (!uploadPropertiesFile.exists()) {
                throw GradleException("Release signing requires android/key.properties and an upload keystore. See docs/google-play-publishing.md, or use tool/build-apk.ps1 for personal APKs.")
            }
            listOf("storeFile", "storePassword", "keyAlias", "keyPassword").forEach { name ->
                if (uploadProperties.getProperty(name).isNullOrBlank()) {
                    throw GradleException("Android key.properties must define $name for upload signing.")
                }
            }
        }
    }
}
tasks.configureEach {
    if (name == "preReleaseBuild" || name == "bundleRelease" || name == "assembleRelease") {
        dependsOn(validateUploadSigning)
    }
}

android {
    namespace = "com.pocketcinema.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.pocketcinema.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("upload") {
            // Release tasks require credentials through validateUploadSigning;
            // they never silently fall back to the development certificate.
            storeFile = uploadProperties.getProperty("storeFile")?.let { rootProject.file(it) }
            storePassword = uploadProperties.getProperty("storePassword")
            keyAlias = uploadProperties.getProperty("keyAlias")
            keyPassword = uploadProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (personalInstall) "debug" else "upload")
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
