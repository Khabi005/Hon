import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val honSigningFile = rootProject.file("key.properties")
val honSigning = Properties().apply { if (honSigningFile.exists()) honSigningFile.inputStream().use { load(it) } }
val honLocalSigning = providers.gradleProperty("honLocalSigning").orNull == "true"

android {
    signingConfigs {
        create("honRelease") {
            if (honSigningFile.exists()) {
                storeFile = rootProject.file(honSigning.getProperty("storeFile"))
                storePassword = honSigning.getProperty("storePassword")
                keyAlias = honSigning.getProperty("keyAlias")
                keyPassword = honSigning.getProperty("keyPassword")
            }
        }
    }
    namespace = "com.hon.reader.hon"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.hon.reader.hon"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Local update builds retain the installed prototype's certificate.
            // Public release builds require the dedicated private signing key.
            if (!honLocalSigning && !honSigningFile.exists() && gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }) error("Configure android/key.properties or explicitly use -PhonLocalSigning=true for an update-compatible local build")
            signingConfig = signingConfigs.getByName(if (honLocalSigning) "debug" else "honRelease")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = false
        }
    }

    testOptions.unitTests.all {
        it.systemProperty("hon.bundledSources", rootProject.file("../assets/sources/bundled").absolutePath)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.fragment:fragment-ktx:1.8.6")
    implementation("org.readium.kotlin-toolkit:readium-shared:3.1.1")
    implementation("org.readium.kotlin-toolkit:readium-streamer:3.1.1")
    implementation("org.readium.kotlin-toolkit:readium-navigator:3.1.1")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    implementation("com.google.guava:guava:33.3.1-android")
    implementation("org.luaj:luaj-jse:3.0.1")
    implementation("org.jsoup:jsoup:1.18.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
}

flutter {
    source = "../.."
}
