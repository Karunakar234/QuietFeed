plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "app.quietfeed.firetv"
    compileSdk = 35

    defaultConfig {
        applicationId = "app.quietfeed.firetv"
        // Fire OS 6 (Android 7.1) and newer: every Fire TV Stick still getting updates.
        minSdk = 25
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    signingConfigs {
        // A fixed debug key, so each new build installs over the last one on the Fire TV.
        // It's Android's standard public debug key, not a secret; use your own key for the Appstore.
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Document-start script injection, the Android equivalent of WKUserScript(.atDocumentStart).
    implementation("androidx.webkit:webkit:1.12.1")
}

/**
 * The filter rules and the page engine are shared with the iOS app: they are copied from
 * ../QuietFeed/Filtering at build time, so a rule change ships to both apps from one file.
 */
abstract class CopySharedFilters : DefaultTask() {
    @get:InputFiles
    abstract val sources: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun copy() {
        val out = outputDir.get().asFile
        out.deleteRecursively()
        out.mkdirs()
        sources.forEach { it.copyTo(out.resolve(it.name), overwrite = true) }
    }
}

val copySharedFilters = tasks.register<CopySharedFilters>("copySharedFilters") {
    val shared = rootProject.file("../QuietFeed/Filtering")
    sources.from(shared.resolve("rules.json"), shared.resolve("FilterEngine.js"))
    outputDir.set(layout.buildDirectory.dir("generated/sharedFilters"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(copySharedFilters, CopySharedFilters::outputDir)
    }
}
