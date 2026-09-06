import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import java.util.Properties

plugins {
    id("com.android.library")
    id("com.vanniktech.maven.publish")
}

val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86" to 3, "x86_64" to 4)
val universalBase = 8000

data class LibassProvider(
    val group: String,
    val artifact: String,
    val version: String,
    val ndkVersion: String,
)

val libassProviderProperties = providers.gradleProperty("libassProviderProperties").orNull
val libassProvider = libassProviderProperties?.let { propertiesPath ->
    val propertiesFile = rootProject.file(propertiesPath)
    val properties = Properties().apply {
        require(propertiesFile.isFile) { "Shared libass provider properties not found: $propertiesFile" }
        propertiesFile.inputStream().use(::load)
    }
    LibassProvider(
        group = requireNotNull(properties.getProperty("group")),
        artifact = requireNotNull(properties.getProperty("artifact")),
        version = requireNotNull(properties.getProperty("version")),
        ndkVersion = requireNotNull(properties.getProperty("ndk_version")),
    )
}
val configuredNativeNdkVersion = providers.gradleProperty("nativeNdkVersion").orNull
    ?: libassProvider?.ndkVersion
require(libassProvider == null || configuredNativeNdkVersion == libassProvider.ndkVersion) {
    "Shared libass provider NDK ${libassProvider?.ndkVersion} does not match MPV NDK $configuredNativeNdkVersion"
}

version = "0.2.1-thor"
group = "io.github.abdallahmehiz"

android {
    namespace = "is.xyz.mpv"
    configuredNativeNdkVersion?.let {
        ndkVersion = it
    }
    compileSdk = 36
    defaultConfig {
        minSdk = 24
        buildConfigField("String", "VERSION", "\"$version\"")
    }

    buildFeatures {
        buildConfig = true
    }

    if (libassProvider != null) {
        packaging {
            jniLibs {
                excludes += "**/libc++_shared.so"
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    tasks.withType<KotlinCompile> {
        compilerOptions.jvmTarget.set(JvmTarget.JVM_11)
    }
}

dependencies {
    api(project(":ffmpeg"))
    if (libassProvider != null) {
        api("${libassProvider.group}:${libassProvider.artifact}:${libassProvider.version}")
    }
    implementation("androidx.appcompat:appcompat:1.8.0")
}

tasks.register<Jar>("sourceJar") {
    archiveClassifier.set("sources")
    from(android.sourceSets["main"].java.srcDirs)
}

mavenPublishing {
    publishToMavenCentral()
    signAllPublications()
    coordinates(
        group.toString(),
        "mpv-android-lib",
        version.toString()
    )
    pom {
        name.set("mpv Android library")
        description.set("The mpv library used by mpvKt.")
        inceptionYear.set("2024")
        url.set("https://github.com/abdallahmehiz/mpv-android/")
        licenses {
            license {
                name.set("MIT License")
                url.set("https://opensource.org/license/mit/")
                distribution.set("repo")
            }
        }
        developers {
            developer {
                id.set("abdallahmehiz")
                name.set("Abdallah Mehiz")
                url.set("https://github.com/abdallahmehiz/")
            }
        }
        scm {
            url.set("https://github.com/abdallahmehiz/mpv-android/")
            connection.set("scm:git:git://github.com/abdallahmehiz/mpv-android.git")
            developerConnection.set("scm:git:ssh://git@github.com/abdallahmehiz/mpv-android.git")
        }
    }
}

