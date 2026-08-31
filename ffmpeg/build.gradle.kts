import java.util.Properties

plugins {
    id("com.android.library")
    id("com.vanniktech.maven.publish")
}

val providerProperties = Properties().apply {
    val propertiesFile = file("src/main/ffmpeg-provider.properties")
    if (propertiesFile.isFile) {
        propertiesFile.inputStream().use(::load)
    }
}

group = "io.github.abdallahmehiz"
version = providerProperties.getProperty("version", "0.0-thor.unbuilt")

android {
    namespace = "is.xyz.mpv.ffmpeg"
    providers.gradleProperty("nativeNdkVersion").orNull?.let {
        ndkVersion = it
    }
    compileSdk = 36
    defaultConfig {
        minSdk = 24
    }
}

mavenPublishing {
    publishToMavenCentral()
    signAllPublications()
    coordinates(
        group.toString(),
        "mpv-ffmpeg-android",
        version.toString(),
    )
    pom {
        name.set("mpv FFmpeg Android provider")
        description.set("The shared FFmpeg libraries used by mpv and Media3 on Android.")
        inceptionYear.set("2026")
        url.set("https://github.com/abdallahmehiz/mpv-android/")
        licenses {
            license {
                name.set("GNU General Public License v3.0")
                url.set("https://www.gnu.org/licenses/gpl-3.0.txt")
                distribution.set("repo")
            }
        }
        scm {
            url.set("https://github.com/abdallahmehiz/mpv-android/")
            connection.set("scm:git:git://github.com/abdallahmehiz/mpv-android.git")
            developerConnection.set("scm:git:ssh://git@github.com/abdallahmehiz/mpv-android.git")
        }
    }
}
