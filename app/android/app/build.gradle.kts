import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release builds must use a private upload keystore, never the shared debug key.
val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseKeyProperties = Properties().apply {
    if (releaseKeyPropertiesFile.exists()) {
        releaseKeyPropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseSigning = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !releaseKeyProperties.getProperty(it).isNullOrBlank() }
val dozApplicationId = providers.gradleProperty("dozApplicationId")
    .orElse("com.example.doz")

android {
    namespace = "com.example.doz"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // The placeholder is for local/debug builds only; release builds reject it until the project owner supplies a unique ID.
        applicationId = dozApplicationId.get()
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeyProperties.getProperty("storeFile"))
                storePassword = releaseKeyProperties.getProperty("storePassword")
                keyAlias = releaseKeyProperties.getProperty("keyAlias")
                keyPassword = releaseKeyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Fail closed when someone requests a release artifact without configuring signing.
gradle.taskGraph.whenReady {
    val requestsRelease = allTasks.any { it.name.contains("Release", ignoreCase = true) }
    if (requestsRelease) {
        val applicationId = dozApplicationId.get()
        val validApplicationId = Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$")
            .matches(applicationId)
        if (applicationId == "com.example.doz" || !validApplicationId) {
            throw GradleException(
                "Release applicationId is still a placeholder or invalid. Set -PdozApplicationId to a unique reverse-DNS ID owned by your project; see docs/DISTRIBUTION.md."
            )
        }
        if (!hasReleaseSigning) {
            throw GradleException(
                "Release signing is not configured. Create android/key.properties and an upload keystore; see docs/DISTRIBUTION.md."
            )
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
