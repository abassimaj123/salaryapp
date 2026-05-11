import java.util.Base64
import java.util.Properties

// Inject FLAVOR dart-define based on active Gradle task
val activeFlavor: String = run {
    val tasks = gradle.startParameter.taskNames.joinToString(" ").lowercase()
    when {
        tasks.contains("uk") -> "uk"
        tasks.contains("ca") -> "ca"
        else                 -> "us"
    }
}
val encodedDefine = Base64.getEncoder().encodeToString("FLAVOR=$activeFlavor".toByteArray())
project.extra["dart-defines"] = encodedDefine

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.salary.us.calculator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    val keystoreProperties = Properties()
    val keystoreFile = rootProject.file("key.properties")
    if (keystoreFile.exists()) keystoreProperties.load(keystoreFile.inputStream())

    signingConfigs {
        create("release") {
            keyAlias      = keystoreProperties["keyAlias"]      as String
            keyPassword   = keystoreProperties["keyPassword"]   as String
            storeFile     = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    defaultConfig {
        applicationId = "com.salary.us.calculator"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val localProps = Properties()
    val localPropsFile = rootProject.file("local.properties")
    if (localPropsFile.exists()) localPropsFile.inputStream().use { localProps.load(it) }

    flavorDimensions += "market"
    productFlavors {
        create("us") {
            dimension = "market"
            applicationId = "com.salary.us.calculator"
            resValue("string", "app_name", "Salary Calculator USA")
            buildConfigField("String", "FLAVOR", "\"us\"")
            manifestPlaceholders["admobAppId"] =
                localProps.getProperty("admob.salary.appId.us", "ca-app-pub-3940256099942544~3347511713")
        }
        create("uk") {
            dimension = "market"
            applicationId = "com.salary.uk.calculator"
            resValue("string", "app_name", "Salary Calculator UK")
            buildConfigField("String", "FLAVOR", "\"uk\"")
            manifestPlaceholders["admobAppId"] =
                localProps.getProperty("admob.salary.appId.uk", "ca-app-pub-3940256099942544~3347511713")
        }
        create("ca") {
            dimension = "market"
            applicationId = "com.salary.ca.calculator"
            resValue("string", "app_name", "Salary Calculator Canada")
            buildConfigField("String", "FLAVOR", "\"ca\"")
            manifestPlaceholders["admobAppId"] =
                localProps.getProperty("admob.salary.appId.ca", "ca-app-pub-3940256099942544~3347511713")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
