extra["splitAarRoots"] = listOf(file("OUTPUT"))
apply(from = file("gradle/restore-split-aars.settings.gradle.kts"))

include(":lib")

include(":ffmpeg")

include(":app")

dependencyResolutionManagement {
    repositories {
        providers.gradleProperty("libassProviderRepository").orNull?.let { providerRepository ->
            exclusiveContent {
                forRepository {
                    maven {
                        name = "libassProvider"
                        url = uri(providerRepository)
                    }
                }
                filter {
                    includeModule("io.github.peerless2012", "libass-android-provider")
                }
            }
        }
    }
}
