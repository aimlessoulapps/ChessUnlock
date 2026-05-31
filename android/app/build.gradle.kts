import java.io.File
import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties from /android/key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystoreProps = keystorePropertiesFile.exists()

if (hasKeystoreProps) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Detect if a release task is being requested
val isReleaseTaskRequested =
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

if (isReleaseTaskRequested) {
    if (!hasKeystoreProps) {
        throw GradleException(
            "Release build blocked: /android/key.properties not found. " +
                    "Create key.properties so release AAB is signed with your upload key."
        )
    }

    val storeFilePath = (keystoreProperties["storeFile"] as String?)?.trim().orEmpty()
    if (storeFilePath.isEmpty()) {
        throw GradleException("Release build blocked: 'storeFile' missing in key.properties")
    }

    val resolvedStoreFile = rootProject.file(storeFilePath)
    if (!resolvedStoreFile.exists()) {
        throw GradleException(
            "Release build blocked: keystore file not found at: ${resolvedStoreFile.absolutePath}"
        )
    }
}

android {
    namespace = "com.aimlessoul.chessunlock"

    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.aimlessoul.chessunlock"
        minSdk = flutter.minSdkVersion
        targetSdk = 35

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystoreProps) {
            create("release") {
                val storeFilePath = (keystoreProperties["storeFile"] as String).trim()
                storeFile = rootProject.file(storeFilePath) // relative to /android
                storePassword = (keystoreProperties["storePassword"] as String).trim()
                keyAlias = (keystoreProperties["keyAlias"] as String).trim()
                keyPassword = (keystoreProperties["keyPassword"] as String).trim()
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        debug {
            // default debug signing
        }

        release {
            // Release MUST be signed with your upload key.
            signingConfig = signingConfigs.getByName("debug")

            // Optional later:
            // isMinifyEnabled = true
            // isShrinkResources = true
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.13.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-crashlytics")
}

/**
 * Debug APK copy fix (Flutter CLI expects build/app/outputs/flutter-apk/app-debug.apk)
 */
val flutterExpectedApkDir = File(rootDir.parentFile, "build/app/outputs/flutter-apk")
val flutterExpectedApk = File(flutterExpectedApkDir, "app-debug.apk")

tasks.register("copyDebugApkToFlutterLocation") {
    doLast {
        val apkRoot = File(buildDir, "outputs/apk")
        val debugApk = apkRoot
            .walkTopDown()
            .firstOrNull { it.isFile && it.extension == "apk" && it.name.endsWith("-debug.apk") }

        flutterExpectedApkDir.mkdirs()

        if (debugApk == null) {
            println("[patch] No debug APK found under: $apkRoot")
            return@doLast
        }

        debugApk.copyTo(flutterExpectedApk, overwrite = true)
        println("[patch] Copied debug APK:")
        println("        from: ${debugApk.absolutePath}")
        println("        to:   ${flutterExpectedApk.absolutePath}")
    }
}

tasks.matching { it.name == "assembleDebug" || it.name == "packageDebug" }.configureEach {
    finalizedBy("copyDebugApkToFlutterLocation")
}

/**
 * Release AAB copy fix (Flutter sometimes can't locate it)
 * Copies:
 *   android/app/build/outputs/bundle/release/app-release.aab
 * to:
 *   build/app/outputs/bundle/release/app-release.aab
 */
val flutterExpectedAabDir = File(rootDir.parentFile, "build/app/outputs/bundle/release")
val flutterExpectedAab = File(flutterExpectedAabDir, "app-release.aab")

tasks.register("copyReleaseAabToFlutterLocation") {
    doLast {
        val aab = File(buildDir, "outputs/bundle/release/app-release.aab")
        flutterExpectedAabDir.mkdirs()

        if (!aab.exists()) {
            println("[patch] No release AAB found at: ${aab.absolutePath}")
            return@doLast
        }

        aab.copyTo(flutterExpectedAab, overwrite = true)
        println("[patch] Copied release AAB:")
        println("        from: ${aab.absolutePath}")
        println("        to:   ${flutterExpectedAab.absolutePath}")
    }
}

// Run copy task after bundleRelease finishes
tasks.matching { it.name == "bundleRelease" }.configureEach {
    finalizedBy("copyReleaseAabToFlutterLocation")
}
